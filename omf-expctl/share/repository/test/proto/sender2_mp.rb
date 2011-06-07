#
# Copyright (c) 2006-2009 National ICT Australia (NICTA), Australia
#
# Copyright (c) 2004-2009 WINLAB, Rutgers University, USA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

# This is an OMF Prototype definition
# This prototype contains a single UDP traffic generator, which uses the
# existing modified application otg2_mp.
# Note: the application 'otg2_mp' was contributed by a student and is not 
# officially supported by the OMF/OML team
#
defPrototype("test:proto:sender2_mp") do |p|
  p.name = "Sender2-Multipath"
  p.description = "A node which transmit a stream of packets over multiple paths"
  # List properties of prototype
  p.defProperty('protocol', 'Protocol to use', 'udpm')
  p.defProperty('generator', 'Generator to use', 'cbr')
  p.defProperty('localHost', 'Host that generate the packets')
  p.defProperty('destinationHost', 'Host to send packets to')
  p.defProperty('debugLevel', 'Level of debug messages to output', 0)
  p.defProperty('disjointPath', 'Flag to use (or not) disjoint paths', 1)


  # Define applications to be installed on this type of node,
  # bind the application properties to the prototype properties.
  #
  p.addApplication("test:app:otg2_mp") {|otg|
    otg.bindProperty('protocol')
    otg.bindProperty('generator')
    otg.bindProperty('udpm:local_host', 'localHost')
    otg.bindProperty('udpm:dst_host', 'destinationHost')
    otg.bindProperty('debug-level', 'debugLevel')
    otg.bindProperty('udpm:disjoint', 'disjointPath')
  end
end
