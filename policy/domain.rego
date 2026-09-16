package main

# example.com is the placeholder domain used in base/ (see CLAUDE.md's "Adding/changing a k8s app or
# infra component" convention) - the replace-domain/prefix-domain components swap it for the real domain
# in every envs/ overlay. It should never survive into rendered/non-base manifests.
deny contains msg if {
	walk(input, [_, value])
	is_string(value)
	contains(value, "example.com")
	msg := "example.com (the placeholder domain) must not appear outside base/ - let the replace-domain/prefix-domain components handle it"
}
