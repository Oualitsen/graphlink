# Shared start/stop recipes. The including Makefile sets NAME, PORT and START_CMD
# (and SKIP_WS=1 for a server without subscriptions).
SERVER_SH := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/server.sh)

start-server:
	SKIP_WS=$(or $(SKIP_WS),0) $(SERVER_SH) start $(NAME) $(PORT) -- $(START_CMD)

stop-server:
	$(SERVER_SH) stop
