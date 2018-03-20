resource "aws_vpc" "main" {
    cidr_block = "172.24.${var.vpc_octet}.0/20"
    enable_dns_hostnames = true
    tags {
        Name = "${var.vpc_name}"
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
}

data "aws_vpc_endpoint_service" "s3" {
    service = "s3"
}

resource "aws_vpc_endpoint" "private-s3" {
    vpc_id = "${aws_vpc.main.id}"
    #service_name = "com.amazonaws.us-east-1.s3"
    service_name = "${data.aws_vpc_endpoint_service.s3.service_name}"
    route_table_ids = ["${aws_route_table.private_user.id}"]
}

resource "aws_internet_gateway" "gw" {
    vpc_id = "${aws_vpc.main.id}"
    tags {
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
}

resource "aws_nat_gateway" "nat_gw" {
    allocation_id = "${aws_eip.nat_gw.id}"
    subnet_id     = "${aws_subnet.public.id}"
    tags {
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
}


resource "aws_route_table" "public" {
    vpc_id = "${aws_vpc.main.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }
     route { 
        #from the commons vpc to the csoc vpc via the peering connection
        cidr_block = "${var.csoc_cidr}"
        vpc_peering_connection_id = "${aws_vpc_peering_connection.vpcpeering.id}"
    }

    tags {
        Name = "main"
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
}

resource "aws_eip" "login" {
  vpc = true
}


resource "aws_eip" "nat_gw" {
  vpc = true
}

resource "aws_eip_association" "login_eip" {
    instance_id = "${aws_instance.login.id}"
    allocation_id = "${aws_eip.login.id}"
}

resource "aws_route_table" "private_user" {
    vpc_id = "${aws_vpc.main.id}"
    route {
        cidr_block = "0.0.0.0/0"
        instance_id = "${aws_instance.proxy.id}"
    }
    route {
        # cloudwatch logs route
        cidr_block = "54.224.0.0/12"
        nat_gateway_id = "${aws_nat_gateway.nat_gw.id}"
    }
    route { 
        #from the commons vpc to the csoc vpc via the peering connection
        cidr_block = "${var.csoc_cidr}"
        vpc_peering_connection_id = "${aws_vpc_peering_connection.vpcpeering.id}"
    }
    tags {
        Name = "private_user"
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
}


resource "aws_route_table_association" "public" {
    subnet_id = "${aws_subnet.public.id}"
    route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "private_user" {
    subnet_id = "${aws_subnet.private_user.id}"
    route_table_id = "${aws_route_table.private_user.id}"
}

resource "aws_subnet" "public" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "172.24.${var.vpc_octet + 0}.0/24"
    map_public_ip_on_launch = true
    tags = "${map("Name", "public", "Organization", "Basic Service", "Environment", var.vpc_name)}"
}


resource "aws_subnet" "private_user" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "172.24.${var.vpc_octet + 1}.0/24"
    map_public_ip_on_launch = false
    tags {
        Name = "private_user"
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
}


data "aws_ami" "public_login_ami" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["ubuntu16-client-1.0.2-*"]
  }

  owners     = ["${var.ami_account_id}"]
}

data "aws_ami" "public_squid_ami" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["ubuntu16-squid-1.0.2-*"]
  }

  owners     = ["${var.ami_account_id}"]
}

resource "aws_ami_copy" "login_ami" {
  name              = "ub16-client-crypt-${var.vpc_name}-1.0.2"
  description       = "A copy of ubuntu16-client-1.0.2"
  source_ami_id     = "${data.aws_ami.public_login_ami.id}"
  source_ami_region = "us-east-1"
  encrypted = true

  tags {
    Name = "login-${var.vpc_name}"
  }
  lifecycle {
      #
      # Do not force update when new ami becomes available.
      # We still need to improve our mechanism for tracking .ssh/authorized_keys
      # User can use 'terraform state taint' to trigger update.
      #
      ignore_changes = ["source_ami_id"]
  }
}

resource "aws_ami_copy" "squid_ami" {
  name              = "ub16-squid-crypt-${var.vpc_name}-1.0.2"
  description       = "A copy of ubuntu16-squid-1.0.2"
  source_ami_id     = "${data.aws_ami.public_squid_ami.id}"
  source_ami_region = "us-east-1"
  encrypted = true

  tags {
    Name = "squid-${var.vpc_name}"
  }
  lifecycle {
      #
      # Do not force update when new ami becomes available.
      # We still need to improve our mechanism for tracking .ssh/authorized_keys
      # User can use 'terraform state taint' to trigger update.
      #
      ignore_changes = ["source_ami_id"]
  }
}


resource "aws_iam_role" "cluster_logging_cloudwatch" {
  name = "${var.vpc_name}_cluster_logging_cloudwatch"
  path = "/"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "cluster_logging_cloudwatch" {
    name = "${var.vpc_name}_cluster_logging_cloudwatch"
    policy = "${data.aws_iam_policy_document.cluster_logging_cloudwatch.json}"
    role = "${aws_iam_role.cluster_logging_cloudwatch.id}"
}


resource "aws_iam_instance_profile" "cluster_logging_cloudwatch" {
  name  = "${var.vpc_name}_cluster_logging_cloudwatch"
  role = "${aws_iam_role.cluster_logging_cloudwatch.id}"
}


resource "aws_instance" "login" {
    ami = "${aws_ami_copy.login_ami.id}"
    subnet_id = "${aws_subnet.public.id}"
    instance_type = "t2.micro"
    monitoring = true
    key_name = "${var.ssh_key_name}"
    vpc_security_group_ids = ["${aws_security_group.ssh.id}", "${aws_security_group.local.id}"]
    iam_instance_profile = "${aws_iam_instance_profile.cluster_logging_cloudwatch.name}"
    tags {
        Name = "${var.vpc_name} Login Node"
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
    lifecycle {
        ignore_changes = ["ami", "key_name"]
    }
    user_data = <<EOF
#!/bin/bash 
sed -i 's/SERVER/login_node-auth-{hostname}-{instance_id}/g' /var/awslogs/etc/awslogs.conf
sed -i 's/VPC/'${var.vpc_name}'/g' /var/awslogs/etc/awslogs.conf
cat >> /var/awslogs/etc/awslogs.conf <<EOM
[syslog]
datetime_format = %b %d %H:%M:%S
file = /var/log/syslog
log_stream_name = login_node-syslog-{hostname}-{instance_id}
time_zone = LOCAL
log_group_name = ${var.vpc_name}
EOM

chmod 755 /etc/init.d/awslogs
systemctl enable awslogs
systemctl restart awslogs
EOF
}

resource "aws_instance" "proxy" {
    ami = "${aws_ami_copy.squid_ami.id}"
    subnet_id = "${aws_subnet.public.id}"
    instance_type = "t2.micro"
    monitoring = true
    source_dest_check = false
    key_name = "${var.ssh_key_name}"
    vpc_security_group_ids = ["${aws_security_group.proxy.id}","${aws_security_group.login-ssh.id}", "${aws_security_group.out.id}"]
    iam_instance_profile = "${aws_iam_instance_profile.cluster_logging_cloudwatch.name}"
    tags {
        Name = "${var.vpc_name} HTTP Proxy"
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
    user_data = <<EOF
#!/bin/bash
sed -i 's/SERVER/http_proxy-auth-{hostname}-{instance_id}/g' /var/awslogs/etc/awslogs.conf
sed -i 's/VPC/'${var.vpc_name}'/g' /var/awslogs/etc/awslogs.conf
cat >> /var/awslogs/etc/awslogs.conf <<EOM
[syslog]
datetime_format = %b %d %H:%M:%S
file = /var/log/syslog
log_stream_name = http_proxy-syslog-{hostname}-{instance_id}
time_zone = LOCAL
log_group_name = ${var.vpc_name}
[squid/access.log]
log_group_name = ${var.vpc_name}
log_stream_name = http_proxy-squid_access-{hostname}-{instance_id}
file = /var/log/squid/access.log*
EOM

chmod 755 /etc/init.d/awslogs
systemctl enable awslogs
systemctl restart awslogs
EOF
    lifecycle {
        ignore_changes = ["ami", "key_name"]
    }
}

resource "aws_route53_zone" "main" {
    name = "internal.io"
    comment = "internal dns server for ${var.vpc_name}"
    vpc_id = "${aws_vpc.main.id}"
    tags {
        Environment = "${var.vpc_name}"
        Organization = "Basic Service"
    }
}

resource "aws_route53_record" "squid" {
    zone_id = "${aws_route53_zone.main.zone_id}"
    name = "cloud-proxy"
    type = "A"
    ttl = "300"
    records = ["${aws_instance.proxy.private_ip}"]
}

# this is for vpc peering
resource "aws_vpc_peering_connection" "vpcpeering" {
  peer_owner_id = "${var.csoc_account_id}"
  peer_vpc_id   = "${var.csoc_vpc_id}"
  vpc_id        = "${aws_vpc.main.id}"
  auto_accept   = true

  tags {
    Name = "VPC Peering between ${var.vpc_name} and csoc_main_vpc"
  }
}
