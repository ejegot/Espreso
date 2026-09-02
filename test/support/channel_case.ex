defmodule EspresoWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest

      @endpoint EspresoWeb.Endpoint
    end
  end

  setup tags do
    Espreso.DataCase.setup_sandbox(tags)
    :ok
  end
end
