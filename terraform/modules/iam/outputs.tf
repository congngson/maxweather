output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node group IAM role"
  value       = aws_iam_role.eks_node.arn
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "aws_lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IRSA role"
  value       = aws_iam_role.aws_lb_controller.arn
}

output "fluent_bit_role_arn" {
  description = "ARN of the Fluent Bit IRSA role"
  value       = aws_iam_role.fluent_bit.arn
}

output "jenkins_instance_profile_name" {
  description = "Name of the Jenkins EC2 instance profile"
  value       = aws_iam_instance_profile.jenkins.name
}

output "lambda_authorizer_role_arn" {
  description = "ARN of the Lambda Authorizer IAM role"
  value       = aws_iam_role.lambda_authorizer.arn
}
