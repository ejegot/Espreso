defmodule EspresoWeb.AdminAvailabilityLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Menu

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Availability")
     |> assign(:categories, Menu.list_products_for_availability())
     |> assign(:flash_note, nil)
     |> assign(:adding?, false)
     |> assign(:adding_category?, false)
     |> assign(:photo_product, nil)
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: Menu.photo_max_bytes()
     )
     |> assign_add_form()
     |> assign_category_form(), layout: false}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    product_id = String.to_integer(id)

    product =
      socket.assigns.categories
      |> Enum.flat_map(& &1.products)
      |> Enum.find(&(&1.id == product_id))

    case product do
      nil ->
        {:noreply, assign(socket, :flash_note, "Product not found.")}

      product ->
        case Menu.update_availability_as(actor, product.id, !product.available) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> assign(:categories, Menu.list_products_for_availability())
             |> assign(
               :flash_note,
               if(product.available,
                 do: "#{product.name} marked unavailable.",
                 else: "#{product.name} marked available."
               )
             )}

          {:error, :unauthorized} ->
            {:noreply,
             assign(socket, :flash_note, "You don’t have permission to change availability.")}

          {:error, _} ->
            {:noreply, assign(socket, :flash_note, "Could not update availability.")}
        end
    end
  end

  def handle_event("open_add", _params, socket) do
    if Authorization.can?(socket.assigns.current_user, :edit_menu) do
      {:noreply,
       socket
       |> cancel_photo_uploads()
       |> assign(:adding?, true)
       |> assign(:adding_category?, false)
       |> assign(:photo_product, nil)
       |> assign(:flash_note, nil)
       |> assign_add_form()}
    else
      {:noreply, assign(socket, :flash_note, "You don’t have permission to add items.")}
    end
  end

  def handle_event("close_add", _params, socket) do
    {:noreply, socket |> cancel_photo_uploads() |> assign(:adding?, false)}
  end

  def handle_event("open_add_category", _params, socket) do
    if Authorization.can?(socket.assigns.current_user, :edit_menu) do
      {:noreply,
       socket
       |> cancel_photo_uploads()
       |> assign(:adding?, false)
       |> assign(:adding_category?, true)
       |> assign(:photo_product, nil)
       |> assign(:flash_note, nil)
       |> assign_category_form()}
    else
      {:noreply, assign(socket, :flash_note, "You don’t have permission to add a category.")}
    end
  end

  def handle_event("close_add_category", _params, socket) do
    {:noreply, assign(socket, :adding_category?, false)}
  end

  def handle_event("open_photo", %{"id" => id}, socket) do
    product = find_product(socket, String.to_integer(id))

    cond do
      not Authorization.can?(socket.assigns.current_user, :edit_menu) ->
        {:noreply, assign(socket, :flash_note, "You don’t have permission to change photos.")}

      is_nil(product) ->
        {:noreply, assign(socket, :flash_note, "Product not found.")}

      true ->
        {:noreply,
         socket
         |> cancel_photo_uploads()
         |> assign(:adding?, false)
         |> assign(:adding_category?, false)
         |> assign(:photo_product, product)
         |> assign(:flash_note, nil)}
    end
  end

  def handle_event("close_photo", _params, socket) do
    {:noreply, socket |> cancel_photo_uploads() |> assign(:photo_product, nil)}
  end

  def handle_event("validate_item", params, socket) do
    item = Map.get(params, "item", socket.assigns.add_form.params)
    {:noreply, assign(socket, :add_form, to_form(item, as: :item))}
  end

  def handle_event("validate_category", params, socket) do
    category = Map.get(params, "category", socket.assigns.category_form.params)
    {:noreply, assign(socket, :category_form, to_form(category, as: :category))}
  end

  def handle_event("validate_photo", _params, socket), do: {:noreply, socket}

  def handle_event("save_item", %{"item" => params}, socket) do
    case Menu.create_product_as(socket.assigns.current_user, params) do
      {:ok, product} ->
        {socket, photo_note} = consume_photo(socket, product)

        {:noreply,
         socket
         |> assign(:adding?, false)
         |> assign_add_form()
         |> assign(:categories, Menu.list_products_for_availability())
         |> assign(:flash_note, "#{product.name} added to the menu.#{photo_note}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:add_form, to_form(params, as: :item))
         |> assign(:flash_note, add_error_message(reason))}
    end
  end

  def handle_event("save_category", %{"category" => params}, socket) do
    case Menu.create_category_as(socket.assigns.current_user, params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> assign(:adding_category?, false)
         |> assign_category_form()
         |> assign_add_form()
         |> assign(:categories, Menu.list_products_for_availability())
         |> assign(:flash_note, "#{category.name} added. You can add items to it now.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:category_form, to_form(params, as: :category))
         |> assign(:flash_note, category_error_message(reason))}
    end
  end

  def handle_event("save_photo", _params, socket) do
    case socket.assigns.photo_product do
      nil ->
        {:noreply, assign(socket, :photo_product, nil)}

      product ->
        {socket, photo_note} = consume_photo(socket, product)

        {:noreply,
         socket
         |> assign(:photo_product, nil)
         |> assign(:categories, Menu.list_products_for_availability())
         |> assign(:flash_note, photo_save_flash(product.name, photo_note))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell
      current={:availability}
      current_user={@current_user}
      page_title="Availability"
      chrome={:bar}
    >
      <main class="staff-admin-main staff-availability" id="staff-availability">
        <p :if={@flash_note} class="staff-admin-note" id="availability-flash">{@flash_note}</p>
        <header class="staff-availability-head">
          <div class="staff-availability-head-copy">
            <p class="staff-availability-eyebrow">Menu</p>
            <h2 class="staff-availability-title">Availability</h2>
            <p class="staff-availability-lede">
              Mark items unavailable when sold out (86). Add a photo from this tablet for QR and POS.
            </p>
          </div>
          <div
            :if={Authorization.can?(@current_user, :edit_menu)}
            class="staff-availability-head-actions"
          >
            <button
              type="button"
              id="availability-add-category"
              class="staff-availability-add staff-availability-add--ghost"
              phx-click="open_add_category"
            >
              Add category
            </button>
            <button
              type="button"
              id="availability-add-item"
              class="staff-availability-add"
              phx-click="open_add"
            >
              Add item
            </button>
          </div>
        </header>

        <section
          :for={category <- @categories}
          class="staff-availability-category"
          id={"availability-category-#{category.name}"}
        >
          <h2>{category.name}</h2>
          <p :if={category.products == []} class="staff-availability-empty">
            No items yet. Add item to put drinks or food here.
          </p>

          <div class="staff-availability-grid">
            <article
              :for={product <- category.products}
              class={[
                "staff-availability-item",
                !product.available && "is-unavailable"
              ]}
              id={"availability-product-#{product.id}"}
            >
              <div class="staff-availability-copy">
                <p class="staff-availability-name">{product.name}</p>
                <p class="staff-availability-state">
                  {if product.available, do: "Available", else: "Unavailable"}
                  {if product.has_custom_photo, do: " · Photo", else: ""}
                </p>
              </div>
              <div class="staff-availability-actions">
                <button
                  :if={Authorization.can?(@current_user, :edit_menu)}
                  type="button"
                  class="staff-availability-toggle"
                  phx-click="open_photo"
                  phx-value-id={product.id}
                  id={"availability-photo-#{product.id}"}
                >
                  Photo
                </button>
                <button
                  type="button"
                  class="staff-availability-toggle"
                  phx-click="toggle"
                  phx-value-id={product.id}
                  id={"availability-toggle-#{product.id}"}
                  aria-label={if(product.available, do: "Mark unavailable", else: "Mark available")}
                >
                  {if product.available, do: "86", else: "Restock"}
                </button>
              </div>
            </article>
          </div>
        </section>
      </main>

      <.modal
        :if={@adding?}
        id="availability-add-modal"
        show
        click_away={false}
        autofocus={false}
        on_cancel={JS.push("close_add")}
      >
        <section class="staff-availability-add-dialog" id="availability-add" aria-label="Add item">
          <h3 class="staff-confirm-dialog-title">Add item</h3>
          <p class="staff-confirm-dialog-copy">
            New items show on the QR menu and POS right away. Photo is optional.
          </p>
          <.form
            for={@add_form}
            id="availability-add-form"
            phx-change="validate_item"
            phx-submit="save_item"
            class="staff-team-form"
          >
            <.input
              field={@add_form[:category]}
              type="select"
              label="Category"
              options={category_options()}
            />
            <.input field={@add_form[:name]} type="text" label="Name" required />

            <.input
              :if={add_value(@add_form, :category) == "HOT"}
              field={@add_form[:hot_price_mode]}
              type="select"
              label="Price"
              options={[{"8oz and 12oz", "sizes"}, {"One price (no size)", "single"}]}
            />

            <.input
              :if={add_value(@add_form, :category) == "FOOD"}
              field={@add_form[:menu_group]}
              type="select"
              label="Group"
              options={food_group_options()}
            />

            <.input
              :if={show_single_price?(@add_form)}
              field={@add_form[:price]}
              type="text"
              label={price_label(@add_form)}
              required
            />

            <.input
              :if={show_hot_sizes?(@add_form)}
              field={@add_form[:price_8oz]}
              type="text"
              label="8oz price"
              required
            />
            <.input
              :if={show_hot_sizes?(@add_form)}
              field={@add_form[:price_12oz]}
              type="text"
              label="12oz price"
              required
            />

            <.photo_picker uploads={@uploads} />

            <div class="staff-confirm-dialog-actions">
              <button
                type="submit"
                class="staff-team-btn staff-team-btn--primary"
                id="availability-add-save"
                phx-disable-with="Saving…"
              >
                Save item
              </button>
              <button
                type="button"
                class="staff-team-btn"
                id="availability-add-cancel"
                phx-click="close_add"
              >
                Cancel
              </button>
            </div>
          </.form>
        </section>
      </.modal>

      <.modal
        :if={@adding_category?}
        id="availability-add-category-modal"
        show
        click_away={false}
        autofocus={false}
        on_cancel={JS.push("close_add_category")}
      >
        <section
          class="staff-availability-add-dialog"
          id="availability-add-category-dialog"
          aria-label="Add category"
        >
          <h3 class="staff-confirm-dialog-title">Add category</h3>
          <p class="staff-confirm-dialog-copy">
            New categories show on this board right away. POS and QR show them after the first item.
          </p>
          <.form
            for={@category_form}
            id="availability-add-category-form"
            phx-change="validate_category"
            phx-submit="save_category"
            class="staff-team-form"
          >
            <.input field={@category_form[:name]} type="text" label="Name" required />

            <div class="staff-confirm-dialog-actions">
              <button
                type="submit"
                class="staff-team-btn staff-team-btn--primary"
                id="availability-add-category-save"
                phx-disable-with="Saving…"
              >
                Save category
              </button>
              <button
                type="button"
                class="staff-team-btn"
                id="availability-add-category-cancel"
                phx-click="close_add_category"
              >
                Cancel
              </button>
            </div>
          </.form>
        </section>
      </.modal>

      <.modal
        :if={@photo_product}
        id="availability-photo-modal"
        show
        click_away={false}
        autofocus={false}
        on_cancel={JS.push("close_photo")}
      >
        <section class="staff-availability-add-dialog" id="availability-photo" aria-label="Item photo">
          <h3 class="staff-confirm-dialog-title">Photo</h3>
          <p class="staff-confirm-dialog-copy">
            {@photo_product.name} — pick a photo from this tablet.
          </p>
          <form
            id="availability-photo-form"
            phx-change="validate_photo"
            phx-submit="save_photo"
            class="staff-team-form"
          >
            <.photo_picker uploads={@uploads} />
            <div class="staff-confirm-dialog-actions">
              <button
                type="submit"
                class="staff-team-btn staff-team-btn--primary"
                id="availability-photo-save"
                phx-disable-with="Saving…"
              >
                Save photo
              </button>
              <button
                type="button"
                class="staff-team-btn"
                id="availability-photo-cancel"
                phx-click="close_photo"
              >
                Cancel
              </button>
            </div>
          </form>
        </section>
      </.modal>
    </.staff_shell>
    """
  end

  defp photo_picker(assigns) do
    ~H"""
    <div class="staff-availability-photo-field">
      <label class="staff-availability-photo-label" for={@uploads.photo.ref}>Photo</label>
      <.live_file_input upload={@uploads.photo} class="staff-availability-photo-input" />
      <p class="staff-availability-photo-hint">JPEG, PNG, or WebP. Max 3 MB.</p>
      <.live_img_preview
        :for={entry <- @uploads.photo.entries}
        entry={entry}
        class="staff-availability-photo-preview"
      />
      <p :for={err <- upload_errors(@uploads.photo)} class="staff-availability-photo-error">
        {photo_upload_error(err)}
      </p>
      <%= for entry <- @uploads.photo.entries, err <- upload_errors(@uploads.photo, entry) do %>
        <p class="staff-availability-photo-error">{photo_upload_error(err)}</p>
      <% end %>
    </div>
    """
  end

  defp assign_add_form(socket) do
    assign(socket, :add_form, to_form(blank_add_params(), as: :item))
  end

  defp assign_category_form(socket) do
    assign(socket, :category_form, to_form(%{"name" => ""}, as: :category))
  end

  defp blank_add_params do
    %{
      "category" => List.first(Menu.category_names()) || "HOT",
      "name" => "",
      "hot_price_mode" => "sizes",
      "price" => "",
      "price_8oz" => "",
      "price_12oz" => "",
      "menu_group" => "Rice Meal"
    }
  end

  defp category_options do
    Enum.map(Menu.category_names(), &{&1, &1})
  end

  defp food_group_options do
    Enum.map(Menu.food_group_names(), &{&1, &1})
  end

  defp add_value(form, key) do
    form.params
    |> Map.get(to_string(key), "")
    |> to_string()
  end

  defp show_hot_sizes?(form) do
    add_value(form, :category) == "HOT" and add_value(form, :hot_price_mode) != "single"
  end

  defp show_single_price?(form), do: not show_hot_sizes?(form)

  defp price_label(form) do
    case add_value(form, :category) do
      category when category in ["COLD", "FRAPPE", "SODA"] -> "16oz price"
      _ -> "Price"
    end
  end

  defp find_product(socket, product_id) do
    socket.assigns.categories
    |> Enum.flat_map(& &1.products)
    |> Enum.find(&(&1.id == product_id))
  end

  defp cancel_photo_uploads(socket) do
    Enum.reduce(socket.assigns.uploads.photo.entries, socket, fn entry, acc ->
      cancel_upload(acc, :photo, entry.ref)
    end)
  end

  defp consume_photo(socket, product) do
    case uploaded_entries(socket, :photo) do
      {[], _} ->
        {socket, ""}

      {_completed, [_ | _]} ->
        {socket, " Photo is still uploading — try Save again."}

      {[_ | _], []} ->
        results =
          consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
            case File.read(path) do
              {:ok, binary} -> {:ok, {binary, entry.client_type}}
              {:error, _} -> {:ok, :error}
            end
          end)

        case results do
          [{binary, type} | _] when is_binary(binary) ->
            case Menu.put_product_photo_as(socket.assigns.current_user, product.id, binary, type) do
              {:ok, _} -> {socket, " Photo saved."}
              {:error, reason} -> {socket, " " <> add_error_message(reason)}
            end

          _ ->
            {socket, ""}
        end
    end
  end

  defp photo_save_flash(name, ""), do: "Choose a photo for #{name}."
  defp photo_save_flash(name, note), do: "#{name}.#{note}"

  defp photo_upload_error(:too_large), do: "Photo is too large (max 3 MB)."
  defp photo_upload_error(:not_accepted), do: "Use a JPEG, PNG, or WebP photo."
  defp photo_upload_error(:too_many_files), do: "One photo only."
  defp photo_upload_error(_), do: "Could not read that photo."

  defp add_error_message(:unauthorized), do: "You don’t have permission to add items."
  defp add_error_message(:name_taken), do: "That name is already on this category."
  defp add_error_message(:invalid_name), do: "Enter a name."
  defp add_error_message(:invalid_price), do: "Enter a price greater than 0."
  defp add_error_message(:invalid_menu_group), do: "Choose a food group."
  defp add_error_message(:unknown_category), do: "That category is missing. Add it first."
  defp add_error_message(:invalid_photo), do: "Use a JPEG, PNG, or WebP photo."
  defp add_error_message(:photo_too_large), do: "Photo is too large (max 3 MB)."
  defp add_error_message(_), do: "Could not add the item."

  defp category_error_message(:unauthorized),
    do: "You don’t have permission to add a category."

  defp category_error_message(:name_taken), do: "That category is already on the menu."
  defp category_error_message(:invalid_name), do: "Enter a category name (letters or numbers)."
  defp category_error_message(_), do: "Could not add the category."
end
