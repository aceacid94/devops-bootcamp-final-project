# DevOps Bootcamp Final Project

---

## 🔗 URL Penting

| Jenis | Pautan |
|---|---|
| 🌐 URL Aplikasi | https://infratify-finalproject-abdulhakim.abdulhakim-devops.com/ |
| 📊 URL Monitoring (prometheus) | https://monitoring-infratify-abdulhakim.abdulhakim-devops.com/targets | 
  📊 URL Monitoring (Grafana) | https://monitoring-infratify-grafana-abdulhakim.abdulhakim-devops.com/d/ad95g45/armada-node-overview?from=now-5m&to=now&timezone=browser&refresh=30s
| 📦 URL Repo | [https://github.com/aceacid94/devops-bootcamp-final-project](https://github.com/aceacid94/devops-bootcamp-final-project) |
    GRAFANA CREDENTIAL: USERNAME: admin | Password: admin


---

## 🗂️ Struktur Repo

```
.
├── scripts/                     # Skrip bantuan (ssm-run.sh, bootstrap-controller.sh, dll)
├── ship/                        # Fail sokongan deployment
├── ec2.tf                       # Definisi instance EC2 (controller, web, monitoring)
├── network.tf                   # VPC, subnet, security group
├── security.tf                  # IAM & security group rules
├── inventory.tf / inventory.ini.tftpl   # Jana inventory Ansible secara dinamik
├── playbook.yaml                # Playbook utama Ansible
├── playbook-web.yaml            # Setup pelayan web
├── playbook-prometheus.yaml     # Setup Prometheus
├── playbook-node-exporter.yaml  # Setup Node Exporter
├── docker-compose.yml           # Definisi kontena aplikasi
├── Deploy.yaml                  # Workflow GitHub Actions: Terraform apply + Ansible run
└── README.md
```

---

## Penerangan file

- update-ssh-config.sh
    - Script ni auto-kemaskini ~/.ssh/config lepas terraform apply, supaya ssh controller sentiasa boleh guna walaupun instance ID EC2 controller berubah setiap kali infra dibina semula

- fix-key-sync,sh
    - Script ni auto-sync SSH public key controller ke pelayan web & monitoring, semua melalui AWS SSM (tanpa SSH manual atau copy-paste key).

- docker-image-push-ecr.sh
    - Script ni build Docker image aplikasi dan push ke AWS ECR (Elastic Container Registry)

## 🛠️ Teknologi Digunakan

- **Terraform** — Infrastructure as Code (EC2, VPC, IAM, Security Groups)
- **Ansible** — Configuration management (Docker, Prometheus, Node Exporter)
- **AWS SSM** — Akses selamat tanpa SSH key terdedah
- **Docker Compose** — Orkestrasi kontena aplikasi
- **Prometheus + Node Exporter** — Monitoring & metrik pelayan

---

## 📄 Lesen

Projek ini dihasilkan untuk tujuan pembelajaran DevOps Bootcamp.
