variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "brazilsouth"
}

variable "publisher_email" {
  description = "Email for APIM publisher"
  type        = string
  default     = "admin@orderhub.com"
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "orderhub"
}
