output "web_ip" {
  value = module.web_server.private_ip
}

output "monitoring_ip" {
  value = module.monitoring_server.private_ip
}

output "ansible_controller" {
  value = "aws ssm start-session --target ${module.ansible_controller.id}"
}

output "controller_instance_id" {
  description = "Instance ID of the Ansible controller"
  value       = module.ansible_controller.id
}

output "web_server_instance_id" {
  description = "Instance ID of the web server"
  value       = module.web_server.id
}

output "monitoring_server_instance_id" {
  description = "Instance ID of the monitoring server"
  value       = module.monitoring_server.id
}
