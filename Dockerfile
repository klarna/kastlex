FROM elixir

WORKDIR /kastlex

# Cache dependencies
COPY mix.exs mix.exs
COPY mix.lock mix.lock
RUN mix local.hex --force
RUN mix deps.get

# Prepare for run
COPY . .
RUN mix deps.get
RUN mix compile
