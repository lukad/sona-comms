defmodule SonaComms.Repo.Migrations.AddPriorityToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :priority, :string
    end

    execute "UPDATE messages SET priority = 'mid' WHERE kind = 'announcement'", ""

    # announcements always have a priority, text messages never do
    create constraint(:messages, :priority_only_on_announcements,
             check: "(kind = 'announcement') = (priority IS NOT NULL)"
           )
  end
end
