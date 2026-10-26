import Config

# This file reads nothing from the environment, deliberately. The
# substrate's config layer is the one reader: every value a deployment
# differs on is a declaration in a system's `config/0`, loaded once at
# boot with one report naming every problem at once (`Oneiroi.Boot`).
# A `System.get_env` here would be a second reader that fails one
# variable per restart, which is the shape the layer exists to end. The
# file stays so the next person reaching for runtime env reading finds
# the argument here.
