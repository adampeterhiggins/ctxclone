GITHUB_REPO := adampeterhiggins/ctxclone
PLUGIN_NAME := ctxclone

.PHONY: install uninstall reinstall

install:
	claude plugin marketplace add $(GITHUB_REPO)
	claude plugin install $(PLUGIN_NAME)@$(PLUGIN_NAME)

uninstall:
	claude plugin uninstall $(PLUGIN_NAME)

reinstall: uninstall install
