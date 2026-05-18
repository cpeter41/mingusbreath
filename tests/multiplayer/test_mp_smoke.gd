# Phase 4 scaffold — multiplayer smoke test.
#
# In-process sanity only: confirms the offline/authority primitives the real
# harness depends on. The two-peer harness (host + client headless processes)
# is described in tests/multiplayer/README.md and not yet built.
#
# Not part of the default `run_tests` scan — invoke explicitly:
#   pwsh tests/run_tests.ps1 multiplayer
extends GdUnitTestSuite


func test_network_manager_starts_offline() -> void:
	assert_bool(NetworkManager.is_offline()).is_true()


func test_offline_peer_is_authority_for_any_node() -> void:
	var n: Node = auto_free(Node.new())
	assert_bool(NetworkManager.is_authority_for(n)).is_true()


func test_authority_router_server_only_runs_when_offline() -> void:
	var ran := [false]
	AuthorityRouter.server_only(func() -> void: ran[0] = true)
	assert_bool(ran[0]).is_true()
