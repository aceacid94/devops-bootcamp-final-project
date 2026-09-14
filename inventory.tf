resource "local_file" "inventory" {
  filename = "inventory.ini"
  content = templatefile("inventory.ini.tftpl", {
    web_ip        = module.web_server.private_ip
    monitoring_ip = module.monitoring_server.private_ip
  })
}
