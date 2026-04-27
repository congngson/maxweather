variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "owm_api_key" {
  type      = string
  sensitive = true
}

variable "demo_api_key" {
  type    = string
  default = "demo-key-maxweather-2026"
}
