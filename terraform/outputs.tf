output "central_public_ip" {
  value = aws_instance.central.public_ip
}
output "edge_public_ips" {
  value = [for e in aws_instance.edge : e.public_ip]
}
output "central_private_ip" {
  value = aws_instance.central.private_ip
}
output "edge_private_ips" {
  value = [for e in aws_instance.edge : e.private_ip]
}