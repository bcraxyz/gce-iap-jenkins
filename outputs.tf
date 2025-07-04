output "jenkins_instance_name" {
  description = "Jenkins VM instance name"
  value = google_compute_instance.jenkins_vm.name
}

output "https_load_balancer_ip" {
  description = "HTTPS load balancer IP address"
  value = google_compute_global_address.jenkins_ip.address
}

output "dns_configuration" {
  description = "DNS configuration needed"
  value       = "Point ${var.domain_name} A record to ${google_compute_global_address.jenkins_ip.address}"
}
