defmodule EspresoWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: EspresoWeb.Gettext

  alias Espreso.CoffeeSpot
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 mr-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8 bg-white">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 min-h-[6rem]",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders CoffeeSpot visit/contact links with brand icons.
  """
  attr :variant, :string, default: "home", values: ~w(home menu contact)
  attr :links, :list, required: true

  def contact_links(assigns) do
    ~H"""
    <ul class={"#{@variant}-visit-links"}>
      <li :for={link <- @links}>
        <a
          href={link.href}
          class={"#{@variant}-visit-link"}
          target={if(link.external?, do: "_blank", else: nil)}
          rel={if(link.external?, do: "noopener noreferrer", else: nil)}
        >
          <span class={"#{@variant}-visit-icon #{@variant}-visit-icon--#{link.id}"} aria-hidden="true">
            <.contact_icon name={link.id} />
          </span>
          <span class={"#{@variant}-visit-link-text"}>
            <span class={"#{@variant}-visit-link-label"}>{link.label}</span>
            <span class={"#{@variant}-visit-link-detail"}>{link.detail}</span>
          </span>
        </a>
      </li>
    </ul>
    """
  end

  @doc """
  Monochrome social icons for the site header (Instagram, Facebook, TikTok).
  """
  def site_socials(assigns) do
    ~H"""
    <nav class="site-top-socials" aria-label="Social">
      <a
        :for={link <- Espreso.CoffeeSpot.social_links()}
        href={link.href}
        class="site-top-social"
        target="_blank"
        rel="noopener noreferrer"
        aria-label={"CoffeeSpot on #{link.label}"}
      >
        <.social_icon name={link.id} />
      </a>
    </nav>
    """
  end

  @doc """
  Minimal Brune-style top bar — logo left, menu link right.
  """
  attr :current, :string, default: "home", values: ~w(home menu about contact)
  attr :show_basket?, :boolean, default: false
  attr :basket_count, :integer, default: 0
  attr :basket_pulse?, :boolean, default: false

  def brune_header(assigns) do
    ~H"""
    <header class="brune-top">
      <div class="brune-top-mobile" aria-label="Mobile navigation">
        <div class="brune-top-mobile-leading">
          <details class="brune-drawer">
            <summary class="brune-icon-btn" aria-label="Open menu">
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M4 7h16M4 12h16M4 17h16" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
              </svg>
            </summary>
            <div class="brune-drawer-panel">
              <nav class="brune-drawer-nav" aria-label="Main">
                <.link navigate="/" class={["brune-drawer-link", @current == "home" && "is-current"]}>
                  Home
                </.link>
                <.link navigate="/menu" class={["brune-drawer-link", @current == "menu" && "is-current"]}>
                  Menu
                </.link>
                <.link navigate="/about" class={["brune-drawer-link", @current == "about" && "is-current"]}>
                  About
                </.link>
                <.link navigate="/contact" class={["brune-drawer-link", @current == "contact" && "is-current"]}>
                  Contact
                </.link>
              </nav>
            </div>
          </details>

          <%= if @current == "menu" do %>
            <button
              type="button"
              class="brune-icon-btn"
              aria-label="Search menu"
              phx-click={JS.focus(to: "#menu-search-input")}
            >
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="1.6" />
                <path d="M16.2 16.2 20 20" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
              </svg>
            </button>
          <% else %>
            <.link navigate="/menu#menu-search" class="brune-icon-btn" aria-label="Search menu">
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="1.6" />
                <path d="M16.2 16.2 20 20" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
              </svg>
            </.link>
          <% end %>
        </div>

        <div class="brune-top-mobile-trailing">
          <.link navigate="/contact" class="brune-icon-btn" aria-label="Contact">
            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.6" />
              <circle cx="12" cy="10" r="3" stroke="currentColor" stroke-width="1.6" />
              <path
                d="M6.8 18.2c1.3-2 3.1-3 5.2-3s3.9 1 5.2 3"
                stroke="currentColor"
                stroke-width="1.6"
                stroke-linecap="round"
              />
            </svg>
          </.link>

          <%= if @show_basket? do %>
            <button
              type="button"
              class={["brune-icon-btn", "brune-icon-bag", @basket_pulse? && "brune-basket-btn-pulse"]}
              phx-click="open_basket"
              aria-label={"Checkout, #{@basket_count} items"}
            >
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path
                  d="M7.5 8.5V7.2a4.5 4.5 0 0 1 9 0v1.3"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linecap="round"
                />
                <path
                  d="M6.2 8.5h11.6l-.7 11.2a1.6 1.6 0 0 1-1.6 1.5H8.5a1.6 1.6 0 0 1-1.6-1.5L6.2 8.5Z"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linejoin="round"
                />
              </svg>
              <span
                :if={@basket_count > 0}
                class={["brune-bag-count", @basket_pulse? && "is-pulse"]}
              >
                {@basket_count}
              </span>
            </button>
          <% else %>
            <.link navigate="/menu" class="brune-icon-btn brune-icon-bag" aria-label="Open menu">
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path
                  d="M7.5 8.5V7.2a4.5 4.5 0 0 1 9 0v1.3"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linecap="round"
                />
                <path
                  d="M6.2 8.5h11.6l-.7 11.2a1.6 1.6 0 0 1-1.6 1.5H8.5a1.6 1.6 0 0 1-1.6-1.5L6.2 8.5Z"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linejoin="round"
                />
              </svg>
            </.link>
          <% end %>
        </div>
      </div>

      <.link navigate="/" class="brune-top-brand">CoffeeSpot</.link>
      <nav class="brune-top-nav" aria-label="Main">
        <.link navigate="/" class={["brune-top-link", @current == "home" && "is-current"]}>Home</.link>
        <.link navigate="/menu" class={["brune-top-link", @current == "menu" && "is-current"]}>Menu</.link>
        <.link navigate="/about" class={["brune-top-link", @current == "about" && "is-current"]}>About</.link>
        <.link navigate="/contact" class={["brune-top-link", @current == "contact" && "is-current"]}>Contact</.link>
      </nav>
      <%= if @show_basket? do %>
        <div class="brune-top-trailing">
          <button
            type="button"
            class={["brune-basket-btn", @basket_pulse? && "brune-basket-btn-pulse"]}
            phx-click="open_basket"
            aria-label={"Checkout, #{@basket_count} items"}
          >
            Checkout
            <span class={["brune-basket-count", @basket_pulse? && "is-pulse"]}>{@basket_count}</span>
          </button>
        </div>
      <% end %>
    </header>
    """
  end

  @doc """
  Home page promo cards — midnight hours and student discount.
  """
  def brune_promos(assigns) do
    ~H"""
    <section class="brune-promos" aria-labelledby="brune-promos-title">
      <header class="brune-promos-head">
        <p class="brune-promos-eyebrow">What's brewing</p>
        <h2 id="brune-promos-title" class="brune-promos-title">Coming this September</h2>
      </header>

      <ul class="brune-promos-grid">
        <li :for={promo <- CoffeeSpot.promo_cards()} class="brune-promo-card">
          <article class="brune-promo-card-inner">
            <figure class="brune-promo-visual">
              <img src={promo.image} alt={promo.image_alt} loading="lazy" />
              <span class="brune-promo-badge">{promo.badge}</span>
            </figure>
            <div class="brune-promo-copy">
              <h3 class="brune-promo-name">{promo.title}</h3>
              <p class="brune-promo-body">{promo.body}</p>
            </div>
          </article>
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  Slim student promo strip for the Menu page.
  """
  def brune_student_promo(assigns) do
    ~H"""
    <aside class="brune-student-promo" aria-label="Student promotion">
      <p class="brune-student-promo-text">{CoffeeSpot.student_promo_note()}</p>
    </aside>
    """
  end

  def brune_cups(assigns) do
    ~H"""
    <svg class="brune-cups" viewBox="0 0 180 220" fill="none" aria-hidden="true">
      <path
        d="M42 118c0-18 10-34 28-38 8-2 16-1 22 2 10-14 28-18 42-8 14 10 16 30 6 44 4 2 8 6 10 12 6 14-2 30-16 34H52c-14-4-22-20-16-34 2-6 4-8 6-12z"
        stroke="currentColor"
        stroke-width="3.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M78 44c0-12 8-22 20-22s20 10 20 22"
        stroke="currentColor"
        stroke-width="3.5"
        stroke-linecap="round"
      />
      <circle cx="68" cy="92" r="3" fill="currentColor" />
      <circle cx="88" cy="92" r="3" fill="currentColor" />
      <path d="M72 104c6 6 16 6 22 0" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
      <path
        d="M98 132c0-16 10-30 24-34 8-2 16 0 22 4 8-12 24-16 36-6 10 8 12 24 4 34 3 2 6 6 8 12 4 12-4 26-16 28H104c-12-2-20-16-16-28 2-6 5-10 10-12z"
        stroke="currentColor"
        stroke-width="3.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <circle cx="118" cy="108" r="3" fill="currentColor" />
      <circle cx="138" cy="108" r="3" fill="currentColor" />
      <path d="M122 120c6 5 14 5 20 0" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
    </svg>
    """
  end

  @doc """
  Shared CoffeeSpot site header for Home, Menu, About, and Contact.
  """
  attr :current, :string, required: true, values: ~w(home menu about contact)
  attr :variant, :string, default: "default", values: ~w(default overlay)
  attr :show_basket?, :boolean, default: false
  attr :basket_count, :integer, default: 0
  attr :basket_pulse?, :boolean, default: false

  def site_header(assigns) do
    ~H"""
    <header class={[
      "site-top",
      @variant == "overlay" && "site-top-over",
      @show_basket? && "site-top-menu"
    ]}>
      <.link navigate="/" class="site-top-brand">CoffeeSpot</.link>
      <nav class="site-top-nav" aria-label="Primary">
        <.link navigate="/" class={["site-top-link", @current == "home" && "is-current"]}>
          Home
        </.link>
        <.link navigate="/menu" class={["site-top-link", @current == "menu" && "is-current"]}>
          Menu
        </.link>
        <.link navigate="/about" class={["site-top-link", @current == "about" && "is-current"]}>
          About us
        </.link>
        <.link navigate="/contact" class={["site-top-link", @current == "contact" && "is-current"]}>
          Get in touch
        </.link>
      </nav>
      <%= if @show_basket? do %>
        <div class="site-top-trailing">
          <.site_socials />
          <button
            type="button"
            class={["menu-basket-btn", @basket_pulse? && "menu-basket-btn-pulse"]}
            phx-click="open_basket"
            aria-label={"Checkout, #{@basket_count} items"}
          >
            Checkout
            <span class={["menu-basket-count", @basket_pulse? && "is-pulse"]}>{@basket_count}</span>
          </button>
        </div>
      <% else %>
        <.site_socials />
      <% end %>
    </header>
    """
  end

  attr :name, :atom, required: true

  def social_icon(%{name: :instagram} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="3.6" y="3.6" width="16.8" height="16.8" rx="5" stroke="currentColor" stroke-width="1.7" />
      <circle cx="12" cy="12" r="3.85" stroke="currentColor" stroke-width="1.7" />
      <circle cx="17.15" cy="6.85" r="1.05" fill="currentColor" />
    </svg>
    """
  end

  def social_icon(%{name: :facebook} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M14.4 8.4V6.85c0-.62.4-1.15 1.05-1.15H17V3.2h-1.95C12.7 3.2 11.2 4.7 11.2 6.7v1.7H9.2v2.5h2v9.4h3.2v-9.4h2.05l.45-2.5h-2.5z" />
    </svg>
    """
  end

  def social_icon(%{name: :tiktok} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M16.55 4.15c.65 1.4 1.9 2.45 3.4 2.85v2.35c-1.4-.08-2.7-.55-3.8-1.35v5.85c0 2.95-2.4 5.35-5.35 5.35S5.45 16.8 5.45 13.85s2.4-5.35 5.35-5.35c.28 0 .55.02.85.08v2.55c-.27-.08-.56-.14-.85-.14-1.5 0-2.7 1.22-2.7 2.72s1.2 2.72 2.7 2.72 2.7-1.22 2.7-2.72V4.15h3.05z" />
    </svg>
    """
  end

  attr :name, :atom, required: true

  def contact_icon(%{name: :instagram} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <defs>
        <linearGradient id="ig-grad" x1="0%" y1="100%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#f58529" />
          <stop offset="45%" stop-color="#dd2a7b" />
          <stop offset="100%" stop-color="#8134af" />
        </linearGradient>
      </defs>
      <rect x="3.5" y="3.5" width="17" height="17" rx="4.5" fill="none" stroke="url(#ig-grad)" stroke-width="1.8" />
      <circle cx="12" cy="12" r="4" fill="none" stroke="url(#ig-grad)" stroke-width="1.8" />
      <circle cx="17.2" cy="6.8" r="1.15" fill="url(#ig-grad)" />
    </svg>
    """
  end

  def contact_icon(%{name: :facebook} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="#1877F2" aria-hidden="true">
      <path d="M14.5 8.5V6.8c0-.7.5-1.3 1.2-1.3H17V3h-2.1C12.4 3 11 4.5 11 6.6v1.9H9v2.7h2V21h3.5v-9.8h2.3l.5-2.7h-2.8z" />
    </svg>
    """
  end

  def contact_icon(%{name: :tiktok} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        fill="#25F4EE"
        d="M16.6 4.2c.7 1.5 2 2.6 3.6 3v2.5c-1.5-.1-2.9-.6-4.1-1.5v6.2c0 3.1-2.5 5.6-5.6 5.6S5 17.5 5 14.4s2.5-5.6 5.6-5.6c.3 0 .6 0 .9.1v2.7c-.3-.1-.6-.2-.9-.2-1.6 0-2.9 1.3-2.9 2.9s1.3 2.9 2.9 2.9 2.9-1.3 2.9-2.9V4.2h3.1z"
        transform="translate(-0.55 0.45)"
      />
      <path
        fill="#FE2C55"
        d="M16.6 4.2c.7 1.5 2 2.6 3.6 3v2.5c-1.5-.1-2.9-.6-4.1-1.5v6.2c0 3.1-2.5 5.6-5.6 5.6S5 17.5 5 14.4s2.5-5.6 5.6-5.6c.3 0 .6 0 .9.1v2.7c-.3-.1-.6-.2-.9-.2-1.6 0-2.9 1.3-2.9 2.9s1.3 2.9 2.9 2.9 2.9-1.3 2.9-2.9V4.2h3.1z"
        transform="translate(0.55 -0.45)"
      />
      <path
        fill="#111111"
        d="M16.6 4.2c.7 1.5 2 2.6 3.6 3v2.5c-1.5-.1-2.9-.6-4.1-1.5v6.2c0 3.1-2.5 5.6-5.6 5.6S5 17.5 5 14.4s2.5-5.6 5.6-5.6c.3 0 .6 0 .9.1v2.7c-.3-.1-.6-.2-.9-.2-1.6 0-2.9 1.3-2.9 2.9s1.3 2.9 2.9 2.9 2.9-1.3 2.9-2.9V4.2h3.1z"
      />
    </svg>
    """
  end

  def contact_icon(%{name: :email} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="3.5" y="5.5" width="17" height="13" rx="2" stroke="#C45C26" stroke-width="1.8" />
      <path d="m4.5 7.5 7.5 5.5 7.5-5.5" stroke="#C45C26" stroke-width="1.8" />
    </svg>
    """
  end

  def contact_icon(%{name: :phone} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M7.2 4.8h2.6l1.1 3.2-1.7 1.2a11.5 11.5 0 0 0 5.6 5.6l1.2-1.7 3.2 1.1v2.6c0 .7-.5 1.3-1.2 1.4-7.2.9-13.2-5.1-12.3-12.3.1-.7.7-1.2 1.5-1.2z"
        stroke="#2F9E44"
        stroke-width="1.8"
      />
    </svg>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(EspresoWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EspresoWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
