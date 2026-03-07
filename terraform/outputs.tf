output "cluster_name" {
  value = aws_eks_cluster.nomad_cluster.name
}

output "cluster_region" {
  value = var.target_region
}