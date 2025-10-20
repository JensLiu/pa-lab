# Top-level Makefile for running all testbenches

TESTBENCHES = decoder register_file datapath alu

.PHONY: all $(TESTBENCHES) clean

# Run all testbenches
all: $(TESTBENCHES)

# Individual testbench targets
$(TESTBENCHES):
	@$(MAKE) -C tb_$@

# Clean all testbenches
clean: $(addprefix clean_,$(TESTBENCHES))

clean_%:
	@$(MAKE) -C tb_$* clean