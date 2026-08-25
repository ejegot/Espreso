defmodule EspresoWeb.StaffHomeLive do
  use EspresoWeb, :live_view

  alias EspresoWeb.StaffAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Phoenix.LiveView.redirect(socket, to: StaffAuth.home_path(socket.assigns.current_user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="staff-app site-page"></div>
    """
  end
end
