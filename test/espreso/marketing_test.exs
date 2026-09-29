defmodule Espreso.MarketingTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Marketing
  alias Espreso.Marketing.ShopRequest
  alias Espreso.Repo

  @valid %{
    "contact_name" => "Ana Cruz",
    "cafe_name" => "Lilac Brew",
    "city" => "Marikina",
    "email" => "Ana@Cafe.PH",
    "mobile" => "09171234567",
    "note" => "Two counters"
  }

  test "creates a pending shop request and normalizes email and phone" do
    assert {:ok, %ShopRequest{} = request} = Marketing.create_shop_request(@valid)
    assert request.contact_name == "Ana Cruz"
    assert request.cafe_name == "Lilac Brew"
    assert request.city == "Marikina"
    assert request.email == "ana@cafe.ph"
    assert request.phone_e164 == "+639171234567"
    assert request.note == "Two counters"
    assert request.status == "pending"
  end

  test "rejects invalid Philippine mobile" do
    assert {:error, changeset} =
             Marketing.create_shop_request(Map.put(@valid, "mobile", "021234567"))

    assert %{mobile: ["must be a Philippine mobile"]} = errors_on(changeset)
  end

  test "requires contact fields" do
    assert {:error, changeset} = Marketing.create_shop_request(%{})
    errors = errors_on(changeset)
    assert errors[:contact_name]
    assert errors[:cafe_name]
    assert errors[:city]
    assert errors[:email]
    assert errors[:mobile]
  end

  test "ignores honeypot submissions without inserting" do
    assert {:ok, :ignored} =
             Marketing.create_shop_request(Map.put(@valid, "company_url", "https://spam.test"))

    assert Repo.aggregate(ShopRequest, :count) == 0
  end

  test "lists pending requests and dismisses as platform owner" do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "CS",
        email: "cs.waitlist@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, request} = Marketing.create_shop_request(@valid)
    assert [%ShopRequest{id: id}] = Marketing.list_pending_shop_requests()
    assert id == request.id

    assert {:ok, dismissed} = Marketing.dismiss_as(owner, request)
    assert dismissed.status == "dismissed"
    assert Marketing.list_pending_shop_requests() == []
  end
end
