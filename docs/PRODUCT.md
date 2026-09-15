# Problem

WhatsApp fails hospitality. Groups are not automatically synced to the employee lifecycle and managers have to manually add/remove staff. Reaching the right people may need hand-mande groups per event.

# Personas

- **Alice**, ops manager, 3 venues - brodcast to one or all sites
- **Bob**, head chef, London - messages staff in the kitchen group
- **Charlie**, FOH, Bristol - sees Bristol and Bristol FOH

# Wedge

In WhatsApp, someone creates a group and an admin adds an employee to it. Membership is a manual action with no link to whether someone still works at the company.

Here, no one creates or adminsters those groups. The org has venues, venues have teams, and staff have memberships (`user`, `venue`, `team`, `role`, `ended_at`). Conversations follow from those memberships.

- Creating a venue or team creates its conversation.
- Adding a membership makes the person a participant in the org, venue, and team conversation.
- Ending a membership removes the person from all those conversations.

The participant list of these conversations is never edited directly. WhatsApp can't do this because it has no knowledge of the organizational structure and employee lifecycle.

# Scope

- Derived conversations - automatic membership
- DMs and ad-hoc groups
- Live messages
- Unread counts
- Announcements with acknowledgement (X of Y read)
- Offboarding removes access
- User switcher in development
- Seeds: 3 venues with 3 teams and 5 staff each, including Alice, Bob, and Charlie

# Non-goals

- Push
- Media
- Native App
- Search
- Quiet Hours
- Rotation

# Demo

Alice posts an allergen announcement that everyone must read. Bob's tab updates live, he acknowledges the read. Alice's read count updates live. Charlie's contract ends and Alice removes their membership from the org, their open chats are closed and no longer accessible.
