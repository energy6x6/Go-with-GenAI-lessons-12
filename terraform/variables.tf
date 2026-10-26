variable "project_name" {
  description = "Prefix shared by the lesson's Lambda functions and API."
  type        = string
  default     = "libratrack"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.project_name))
    error_message = "Use a lowercase prefix of 1 to 40 letters, digits or hyphens."
  }
}

variable "region" {
  description = "Регіон AWS (у Floci працює будь-який опублікований регіон)."
  type        = string
  default     = "us-east-1"
}

variable "floci_endpoint" {
  description = "Адреса Floci."
  type        = string
  default     = "http://localhost:4566"
}

variable "lambda_architecture" {
  description = <<-EOT
    Архітектура Lambda: "x86_64" або "arm64". МАЄ збігатися з тим, як зібрано
    бінарник (GOARCH) і з архітектурою Docker-хоста — Floci за замовчуванням
    запускає контейнери в архітектурі хоста. scripts/env.sh виставляє
    TF_VAR_lambda_architecture автоматично.
  EOT
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "lambda_architecture має бути x86_64 або arm64."
  }
}

variable "covers_bucket" {
  type    = string
  default = "libratrack-covers"
}

variable "thumbnails_bucket" {
  type    = string
  default = "libratrack-thumbnails"
}

variable "stage_name" {
  type    = string
  default = "dev"
}
