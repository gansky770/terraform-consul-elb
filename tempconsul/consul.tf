resource "aws_instance" "server" {
  ami             = var.ami["${var.region}-${var.platform}"]
  instance_type   = var.instance_type
  key_name        = var.key_name
  count           = var.servers
  security_groups = [aws_security_group.consul.id]
  subnet_id       = var.subnets[count.index % var.servers]

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.user[var.platform]
    private_key = file(var.key_path)
  }

  #Instance tags
  tags = {
    Name       = "${var.tagName}-${count.index}"
    ConsulRole = "Server"
  }
 # add remote exec
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y install nginx",
      "sudo service nginx start",
    ]
  }
   
  
#   provisioner "file" {
#     source      = "${path.module}/shared/scripts/${var.service_conf[var.platform]}"
#     destination = "/tmp/${var.service_conf_dest[var.platform]}"
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "echo ${var.servers} > /tmp/consul-server-count",
#       "echo ${aws_instance.server[0].private_ip} > /tmp/consul-server-addr",
#     ]
#   }

#   provisioner "remote-exec" {
#     scripts = [
#       "${path.module}/shared/scripts/install.sh",
#       "${path.module}/shared/scripts/service.sh",
#       "${path.module}/shared/scripts/ip_tables.sh",
#     ]
#   }
 }

resource "aws_security_group" "consul" {
  name        = "consul_${var.platform}"
  description = "Consul internal traffic + maintenance."
  vpc_id      = var.vpc_id

  // These are for internal traffic
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    self      = true
  }

  // These are for maintenance
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   // These are for ELB
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    #cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.elb.id]
  }

  // This is for outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

 #add sg
resource "aws_security_group" "elb" {
  name        = "elb_nginx"
  description = "elb external traffic ."
 # vpc_id      = var.vpc_id

  // This is for outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



# add rule
resource "aws_security_group_rule" "elb-sec-rule" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  #security_group_id = "sg-fc5d87bc"
  security_group_id = aws_security_group.elb.id
 }

resource "aws_elb" "terra-elb" {
  name               = "terra-elb"
  availability_zones =  ["eu-west-1a","eu-west-1b","eu-west-1c"]
  security_groups = [aws_security_group.elb.id]



  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = aws_instance.server.*.id
  cross_zone_load_balancing   = true
  idle_timeout                = 100
  connection_draining         = true
  connection_draining_timeout = 300

}

