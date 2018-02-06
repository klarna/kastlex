FROM elixir

WORKDIR /kastlex

# Cache dependencies
COPY mix.exs mix.exs
COPY mix.lock mix.lock
RUN mix local.hex --force && mix local.rebar --force

# Prepare for run
COPY . .
RUN mix deps.get && mix compile
