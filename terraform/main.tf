# --- 0. DATA SOURCES ---
# Automatically gets your AWS Account ID and ARN for the Access Entry
data "aws_caller_identity" "current" {}

# --- 1. NETWORK (VPC) ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  # Dynamic name prevents collisions during regional migration
  name = "nomad-vpc-${var.target_region}"
  cidr = "10.0.0.0/16"

  azs             = ["${var.target_region}a", "${var.target_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = "nomad-cluster-${var.target_region}"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = { Project = "Nomad" }
}

# --- 2. GLOBAL DATABASE ---
resource "aws_dynamodb_table" "nomad_store" {
  name         = "nomad-global-store-v2"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ID"
  range_key    = "Timestamp"

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "ID"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  lifecycle {
    ignore_changes = [replica]
  }
} 

# --- 3. IAM ROLES (CLUSTER & NODES) ---
resource "aws_iam_role" "eks_cluster_role" {
  name = "nomad-cluster-role-${var.target_region}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "node_role" {
  name = "NomadEKSNodeRole-${var.target_region}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])
  policy_arn = each.value
  role       = aws_iam_role.node_role.name
}

resource "aws_eks_cluster" "nomad_cluster" {
name     = "nomad_cluster-${var.target_region}"
role_arn = aws_iam_role.eks_cluster_role.arn
version  = "1.31"


  # Fixes the "Credentials" error by explicitly trusting your IAM user 
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}


# --- 5. IDENTITY & OIDC (FOR POD PERMISSIONS) ---
data "tls_certificate" "eks" {
  url = aws_eks_cluster.nomad_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.nomad_cluster.identity[0].oidc[0].issuer
}

# --- 6. APP DATA PERMISSIONS (IRSA) ---
resource "aws_iam_policy" "dynamodb_access" {
  name   = "NomadDynamoDBAccess-${var.target_region}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Query", "dynamodb:Scan"]
      Effect   = "Allow"
      Resource = [aws_dynamodb_table.nomad_store.arn, "${aws_dynamodb_table.nomad_store.arn}/index/*"]
    }]
  })
}

module "nomad_db_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"
  role_name = "nomad-db-reader-${var.target_region}"
  role_policy_arns = { policy = aws_iam_policy.dynamodb_access.arn }
  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["default:nomad-sa"]
    }
  }
}

# --- 7. UPGRADED MANAGED NODE GROUPS (FIXES RAM ISSUES) ---

# System Node: Management services
resource "aws_eks_node_group" "system_nodes" {
  cluster_name    = aws_eks_cluster.nomad_cluster.name
  node_group_name = "system-pool"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = module.vpc.private_subnets

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  # UPGRADED: t3.large (8GB RAM) prevents NodeNotReady crashes [cite: 8]
  instance_types = ["t3.large"]
  capacity_type  = "ON_DEMAND"

  labels = { "intent" = "control-plane" }

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}

# Workload Node: Application pool
resource "aws_eks_node_group" "managed_nodes" {
  cluster_name    = aws_eks_cluster.nomad_cluster.name
  node_group_name = "nomad-workload-pool"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = module.vpc.private_subnets

  scaling_config {
    desired_size = 2 
    max_size     = 5 
    min_size     = 1
  }

  # UPGRADED: t3.large provides headroom for 4+ app pods [cite: 9]
  instance_types = ["t3.large"]
  capacity_type  = "SPOT" 

  labels = { "intent" = "apps" }

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}