locals {
  name    = "lamp_stack"
  db_name = "lamp_db"
}

# --------------------------------------------------------------------------
# The different modules are loaded from *module.tf in the current directory.
# Each module is responsible for a specific part of the LAMP stack.
# --------------------------------------------------------------------------