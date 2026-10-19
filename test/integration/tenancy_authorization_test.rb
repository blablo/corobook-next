require "test_helper"

# A probe controller that uses the real concerns, drawn into the routes only for this test.
class TenancyProbeController < ApplicationController
  before_action :require_sign_in
  before_action :require_admin, only: :admin_only

  def admin_only = head(:ok)

  # Loads a user from the current church; a cross-church id must 404 via find_in_church.
  def scoped_show
    find_in_church(:users, params[:id])
    head :ok
  end
end

class TenancyAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @central = Church.create!(name: "Central")
    @norte = Church.create!(name: "Norte")
    @admin = User.create!(church: @central, email: "admin@example.com", password: "secret123", role: "admin")
    @editor = User.create!(church: @central, email: "editor@example.com", password: "secret123", role: "editor")
    @foreigner = User.create!(church: @norte, email: "foreign@example.com", password: "secret123", role: "admin")
  end

  def with_probe_routes
    with_routing do |set|
      set.draw do
        get "login" => "sessions#new", as: :login
        post "login" => "sessions#create"
        get "probe/admin_only" => "tenancy_probe#admin_only"
        get "probe/users/:id" => "tenancy_probe#scoped_show"
      end
      yield
    end
  end

  def sign_in_as(user, church)
    post "/login", params: { church_id: church.id, email: user.email, password: "secret123" }
  end

  test "editor is denied an admin-only action" do
    with_probe_routes do
      sign_in_as(@editor, @central)
      get "/probe/admin_only"
      assert_redirected_to login_path
      assert_equal "You are not allowed to do that.", flash[:alert]
    end
  end

  test "admin is allowed the admin-only action" do
    with_probe_routes do
      sign_in_as(@admin, @central)
      get "/probe/admin_only"
      assert_response :ok
    end
  end

  test "accessing another church's record returns 404" do
    with_probe_routes do
      sign_in_as(@admin, @central)
      get "/probe/users/#{@foreigner.id}"
      assert_response :not_found
    end
  end

  test "accessing an own-church record succeeds" do
    with_probe_routes do
      sign_in_as(@admin, @central)
      get "/probe/users/#{@editor.id}"
      assert_response :ok
    end
  end
end
