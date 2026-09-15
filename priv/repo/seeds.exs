# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It only goes through the contexts, so conversations and participants are
# derived from memberships exactly as they are in the app. It refuses to run
# on a non-empty database: use `mix ecto.reset` to start over.
#
#   * Sona Hospitality Group: London, Manchester and Bristol, each with a
#     Kitchen, FOH and Bar team
#   * 5 people per team (1 manager + 4 staff), 45 in total, including
#     Bob (London · Kitchen manager) and Charlie (Bristol · FOH staff)
#   * Alice: venue-level admin at every venue

alias SonaComms.Accounts
alias SonaComms.Accounts.{Scope, User}
alias SonaComms.Chat
alias SonaComms.Org
alias SonaComms.Org.Organisation
alias SonaComms.Repo

if Repo.exists?(User) or Repo.exists?(Organisation) do
  raise """
  the database is not empty, so the seeds were not run.

  Run `mix ecto.reset` to drop, recreate and seed it.
  """
end

venue_names = ~w(London Manchester Bristol)
team_names = ~w(Kitchen FOH Bar)

# 43 people besides Alice, Bob and Charlie, assigned in roster order
names = ~w(Aisha Ben Chloe Daniel Ella Finn Grace Harry Isla Jack Keira Leo Maya Noah
           Olivia Priya Quinn Rosa Sam Tara Umar Vera Will Xander Yasmin Zane Amelia
           Ravi Freya Oscar Lily Theo Hana Marcus Nina Omar Poppy Rhys Sofia Tom Zara
           Kai Mia)

{:ok, org} = Org.create_organisation(%{name: "Sona Hospitality Group"})
system = Scope.for_system(org.id)

venues =
  Map.new(venue_names, fn name ->
    {:ok, venue} = Org.create_venue(system, %{name: name})
    {name, venue}
  end)

teams =
  for venue_name <- venue_names, team_name <- team_names, into: %{} do
    {:ok, team} = Org.create_team(system, venues[venue_name].id, %{name: team_name})
    {{venue_name, team_name}, team}
  end

add_membership = fn name, venue, team, role ->
  {:ok, membership} =
    Org.create_membership(system, %{
      "email" => "#{String.downcase(name)}@sona.test",
      "name" => name,
      "venue_id" => venue.id,
      "team_id" => team && team.id,
      "role" => role
    })

  membership
end

for venue_name <- venue_names do
  add_membership.("Alice", venues[venue_name], nil, "admin")
end

# slot 0 is the team's manager
roster = for venue <- venue_names, team <- team_names, slot <- 0..4, do: {venue, team, slot}

{assignments, []} =
  Enum.map_reduce(roster, names, fn
    {"London", "Kitchen", 0} = slot, pool -> {{"Bob", slot}, pool}
    {"Bristol", "FOH", 1} = slot, pool -> {{"Charlie", slot}, pool}
    slot, [name | pool] -> {{name, slot}, pool}
  end)

for {name, {venue_name, team_name, slot}} <- assignments do
  role = if slot == 0, do: "manager", else: "staff"
  add_membership.(name, venues[venue_name], teams[{venue_name, team_name}], role)
end

## Sample messages

scope_for = fn name ->
  user = Accounts.get_user_by_email("#{String.downcase(name)}@sona.test")
  {:ok, scope} = Org.put_member_scope(Scope.for_user(user))
  scope
end

post = fn name, title, body ->
  scope = scope_for.(name)
  conversation = Enum.find(Chat.list_conversations(scope), &(&1.title == title))
  {:ok, _message} = Chat.post_message(scope, conversation.id, %{"body" => body})
end

team_members = fn venue_name, team_name ->
  for {name, {^venue_name, ^team_name, _slot}} <- assignments, do: name
end

[_bob, cook_1, cook_2 | _] = team_members.("London", "Kitchen")
[foh_manager | _] = team_members.("Bristol", "FOH")

post.("Alice", "Sona Hospitality Group", """
Welcome to Sona 👋 This chat is the whole group, across every venue. Your venue and \
team chats are set up for you, so you'll always be in the right ones.\
""")

post.(
  "Bob",
  "London · Kitchen",
  "Morning team. The veg delivery is running 30 minutes late, so start prep with the sauces."
)

post.(cook_1, "London · Kitchen", "Got it, chef. I'll get the stocks on first.")
post.(cook_2, "London · Kitchen", "We're low on shallots. OK to borrow some from the bar?")
post.("Bob", "London · Kitchen", "Yes, go ahead. I'll add them to tomorrow's order.")

post.(
  foh_manager,
  "Bristol · FOH",
  "Reminder: 40 covers tonight, including a party of 12 at 8pm."
)

post.("Charlie", "Bristol · FOH", "I can take the party table.")
post.(foh_manager, "Bristol · FOH", "Perfect, thanks Charlie.")

IO.puts("""
Seeded #{org.name}: #{map_size(venues)} venues, #{map_size(teams)} teams and \
#{length(assignments) + 1} people.
Switch between people at http://localhost:4000/dev/switch-user
""")
