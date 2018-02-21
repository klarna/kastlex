FROM elixir

WORKDIR /kastlex
ENV MIX_ENV prod

# Cache dependencies
COPY mix.exs mix.exs
COPY mix.lock mix.lock
RUN mix local.hex --force && mix local.rebar --force

# Prepare for run
COPY . .
RUN mix deps.get --only prod && mix compile
