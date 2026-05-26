output "controller_instance_name" {
  description = "Name of the controller instance"
  value       = incus_instance.controller.name
}

output "compute_instance_names" {
  description = "Names of the compute instances"
  value       = incus_instance.compute[*].name
}