defmodule Espreso.CustomersTest do
  use Espreso.DataCase, async: true

  alias Espreso.Customers
  alias Espreso.Customers.Customer
  alias Espreso.Repo

  describe "normalize_phone/1" do
    test "normalizes common PH mobile formats" do
      assert Customers.normalize_phone("09171234567") == {:ok, "+639171234567"}
      assert Customers.normalize_phone("9171234567") == {:ok, "+639171234567"}
      assert Customers.normalize_phone("639171234567") == {:ok, "+639171234567"}
      assert Customers.normalize_phone("+639171234567") == {:ok, "+639171234567"}
      assert Customers.normalize_phone("0917-123-4567") == {:ok, "+639171234567"}
      assert Customers.normalize_phone(" +63 917 123 4567 ") == {:ok, "+639171234567"}
    end

    test "rejects invalid numbers" do
      assert Customers.normalize_phone("021234567") == {:error, :invalid_phone}
      assert Customers.normalize_phone("08171234567") == {:error, :invalid_phone}
      assert Customers.normalize_phone("123") == {:error, :invalid_phone}
      assert Customers.normalize_phone("") == {:error, :invalid_phone}
      assert Customers.normalize_phone(nil) == {:error, :invalid_phone}
      assert Customers.normalize_phone("+14155552671") == {:error, :invalid_phone}
    end
  end

  describe "find_or_create_by_phone/2" do
    test "creates with optional name and unique normalized phone" do
      assert {:ok, customer} =
               Customers.find_or_create_by_phone("09171110001", %{name: "Ana"})

      assert customer.phone_e164 == "+639171110001"
      assert customer.name == "Ana"
      assert customer.points_balance == 0
      assert customer.spend_remainder_centavos == 0

      assert {:ok, same} = Customers.find_or_create_by_phone("9171110001", %{})
      assert same.id == customer.id

      assert {:error, %Ecto.Changeset{} = cs} =
               %Customer{}
               |> Customer.changeset(%{phone_e164: "+639171110001"})
               |> Repo.insert()

      assert %{phone_e164: _} = errors_on(cs)
    end

    test "allows creating without name" do
      assert {:ok, customer} = Customers.find_or_create_by_phone("09171110002")
      assert is_nil(customer.name)
    end
  end
end
