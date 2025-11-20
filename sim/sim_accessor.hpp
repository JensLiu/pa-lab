template <typename SimClass> class SimAccessor {
  const SimClass *sim;

public:
  SimAccessor(const SimClass *sim) : sim(sim) {}
  const SimClass *get_sim() const { return sim; }
	
};