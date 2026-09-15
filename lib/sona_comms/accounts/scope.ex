defmodule SonaComms.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `SonaComms.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user.

  The scope only holds plain values. `organisation_id` and `admin?` are set
  by `SonaComms.Org.put_member_scope/1` when a member LiveView mounts.
  `admin?` is a cache for UI gating only and is never trusted for writes:
  contexts re-check the database.

  `for_system/1` builds a privileged scope with no user. It is only used by
  seeds and tests to bootstrap an organisation through the normal context
  functions.
  """

  alias SonaComms.Accounts.User

  defstruct user: nil, organisation_id: nil, admin?: false, system?: false

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Creates a system scope for the given organisation. Seeds and tests only.
  """
  def for_system(organisation_id) do
    %__MODULE__{organisation_id: organisation_id, system?: true}
  end

  @doc """
  Returns the cached admin flag. For UI gating only.
  """
  def admin?(%__MODULE__{admin?: admin?}), do: admin?
  def admin?(_), do: false
end
