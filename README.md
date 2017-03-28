# MoldableILP

## About

This repository contains the source code used to
produce the simulation results of the following
publication (which is currently in print).

R. Bleuse; S. Hunold; S. Kedad-Sidhoum; F. Monna; G. Mounie; D. Trystram, "Scheduling Independent Moldable Tasks on Multi-Cores with GPUs," in IEEE Transactions on Parallel and Distributed Systems , vol.PP, no.99, pp.1-1
doi: 10.1109/TPDS.2017.2675891

http://ieeexplore.ieee.org/document/7867044/

## Prerequistes

- a MIP solver, either
  - GLPK
  - IBM CPLEX
  - Gurobi
- Julia 0.4 (the code has not been ported to nor tested with Julia 0.5 yet)
  - JuMP
- Python 2.7
  - jinja2


## Examples

### Test1

In directory `examples/test1` you can find a shell script that shows
you how to run the scheduling benchmark with a few smaller instances.

### Test2

The directory `examples/test2` contains a shell script to generate
the instances used in the paper. You can then use these instances
to reproduce the results from the paper (combining `test1` with the
  instances from `test2`).
