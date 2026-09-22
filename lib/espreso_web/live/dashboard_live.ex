defmodule EspresoWeb.DashboardLive do
  use EspresoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/staff")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="sr-only">Redirecting to Home</div>
    """
  end
end
