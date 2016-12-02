defmodule Kastlex.SecretKey do

  @default_secret_key "yCWR+HlWNjnBzh1UsGducT9Irq8zmAWxMbPUV+e3S70cPXeJRMz62y5xDtB3qCRL"

  def fetch do
    case System.get_env("KASTLEX_SECRET_KEY_FILE") do
      nil -> @default_secret_key
      file -> JOSE.JWK.from_file(file)
    end
  end

end
