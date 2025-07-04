output "mautic_instance_name" {
  description = "Mautic VM instance name"
  value = google_compute_instance.mautic_vm.name
}

output "https_load_balancer_ip" {
  description = "HTTPS load balancer IP address"
  value = google_compute_global_address.mautic_ip.address
}

output "dns_configuration" {
  description = "DNS configuration needed"
  value       = "Point ${var.domain_name} A record to ${google_compute_global_address.mautic_ip.address}"
}
