# Repseat

Start two local nodes in three shells, they should connect automatically:

> R_NODES='ra1@127.0.0.1,ra2@127.0.0.1,ra3@127.0.0.1' iex --name ra1@127.0.0.1 -S mix

> R_NODES='ra1@127.0.0.1,ra2@127.0.0.1,ra3@127.0.0.1' iex --name ra2@127.0.0.1 -S mix

> R_NODES='ra1@127.0.0.1,ra2@127.0.0.1,ra3@127.0.0.1' iex --name ra3@127.0.0.1 -S mix

A leader election is triggered if a leader crashes.

# Node addressing:

* `node` format: `{:node, :"NAME@IP"}`
  * e.g. `{:node, :"ra1@127.0.0.1"}`

* API usage:
  * `Repseat.Raft.Machine.create_user({:node, node()}, "Max Mustermann", "mail@e.com",
    "safepassword")`
  * `Repseat.Raft.Machine.create_user("Max Mustermann", "mail@e.com",
