output "mautic_instance_name" {
  description = "Mautic VM instance name"
  value = google_compute_instance.mautic_vm.name
}

output "https_load_balancer_ip" {
  description = "HTTPS load balancer IP address"
  value = google_compute_global_forwarding_rule.https_forwarding_rule.ip_address
}
