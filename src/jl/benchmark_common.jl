###############################################################################
# SCHEDULING INDEPENDENT MOLDABLE TASKS ON MULTI-CORES WITH GPUS
# Copyright (C) 2015 Sascha Hunold <sascha@hunoldscience.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
###############################################################################

using Logging

function get_output_file_names(instance_fname::AbstractString, output_dirname::AbstractString, algid::AbstractString)

  if endswith(instance_fname, ".in")
    name_without_suffix = replace(instance_fname, ".in", "")
  elseif endswith(instance_fname, ".in.bz2")
    name_without_suffix = replace(instance_fname, ".in.bz2", "")
  end

  new_prefix = name_without_suffix * "_" * algid

#  out_fname = joinpath(output_dirname, new_prefix * ".out")
  jed_fname = joinpath(output_dirname, new_prefix * ".jed")
  csv_fname = joinpath(output_dirname, new_prefix * ".csv")

  d = Dict(
#    "out_fname" => out_fname,
    "jed_fname" => jed_fname,
    "csv_fname" => csv_fname
  )
  d
end
