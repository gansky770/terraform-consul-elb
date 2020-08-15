output "elb_address" {
  value = aws_elb.terra-elb.dns_name
}

