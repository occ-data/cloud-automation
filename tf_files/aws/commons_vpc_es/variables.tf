
variable "vpc_name" {}
variable "vpc_id" {}

variable "vpc_octet2" {
  default = 24
}

variable "vpc_octet3" {
  default = 48
}

variable "csoc_account_id" {
  default = "433568766270"
}

variable "csoc_cidr" {
  default = "10.128.0.0/20"
}
