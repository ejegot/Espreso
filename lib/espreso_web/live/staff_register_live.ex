defmodule EspresoWeb.StaffRegisterLive do
  @moduledoc """
  Legacy `/register` route.

  Public registration is closed. Empty databases are sent to Initial Owner Setup;
  initialized systems redirect to the unified login.
  """
  use EspresoWeb, :live_view

  alias Espreso.Accounts

  @impl true
  def mount(_params, _session, socket) do
    target =
      if Accounts.needs_initial_owner_setup?() do
        ~p"/setup"
      else
        ~p"/login"
      end

    {:ok, push_navigate(socket, to: target)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="staff-auth-page">
      <p class="staff-auth-subtitle">Redirecting…</p>
    </div>
    """
  end
end
