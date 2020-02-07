FROM elixir

WORKDIR /kastlex
ENV MIX_ENV prod

# Cache dependencies
COPY mix.exs mix.exs
COPY mix.lock mix.lock
RUN mix local.hex --force && mix local.rebar --force

# Prepare for run
COPY . .
RUN mix deps.get --only prod && \
    mix compile && \
    mix release

ENV KASTLEX_JWK_FILE="/kastlex/priv/jwk.pem"
CMD ["./_build/prod/rel/kastlex/bin/kastlex", "start"]
