# Automatically syncs the controller's SSH key to both target servers
# every time terraform apply runs, eliminating the manual fix-key-sync.sh step.
resource "null_resource" "sync_ansible_key" {
  # Re-run whenever any of the 3 instances change (i.e. every rebuild)
  triggers = {
    controller_id = module.ansible_controller.id
    web_id        = module.web_server.id
    monitoring_id = module.monitoring_server.id
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/fix-key-sync.sh"
    interpreter = ["bash", "-c"]
  }

  depends_on = [
    module.ansible_controller,
    module.web_server,
    module.monitoring_server
  ]
}
