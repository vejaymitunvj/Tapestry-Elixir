# Implementation of Tapestry Algorithm to find maximum number of hops taken by the nodes to reach the root node .

### Group Members:         
  * Muthu Kumaran Manoharan   (UFID# 9718-4490)
  * Vejay Mitun Venkatachalam Jayagopal (UFID# 3106-5997)

### Steps to run code:
  * Create a new mix project using command “mix new tapestry”
  * Extract zip file file containing tapestry.ex, project3.exs and mix.exs files.
  * Copy project3.exs and mix.exs to the project folder created.(Replace the default mix.exs file created with ours)
  * Delete the default project3.ex created in the lib folder and copy our tapestry.ex to the lib folder.
  *	Open cmd or terminal , run project by issuing commands “mix compile” and  “mix run –-no-halt project3.exs <node #> <# request/node>” for the project to run continuously and terminate it when the results are received.
    * eg #1: mix run --no-halt project3.exs 10000 5
	* eg #2: mix run --no-halt project3.exs 5000 100
	* eg #3  mix run --no-halt project3.exs 1000 100

#### What is working :

As per the section 3 specifications of the Tapestry protocol in the paper :- 

Tapestry: A Resilient Global-Scale Overlay for Service Deployment by Ben Y. Zhao, Ling Huang, Jeremy Stribling, Sean C. Rhea, Anthony D. Joseph and John D. Kubiatowicz. (Link to paper- https://pdos.csail.mit.edu/~strib/docs/tapestry/tapestry_jsac03.pdf),

we have implemented object location, routing & network join as described in the paper. We have built a routing table for each node and populating it with the nearest node.(Here we are taking the node with their nearest hex value as the closest node since this is a simualtion. We are not considering the latency as a measure of the distance here). 

We are using sha1 as the hash function. Our node IDs are the 8 digit truncated hex value of the sha1 hash function. Hence our table has 8 rows and 16 columns.

When creating the network we are creating N-1 nodes (N being the number of nodes required) in one go and then spawning and adding the last node. We then trigger the nodes to start their message sending process where each node will send the required number of requests per sec till we have reached the quota.

Our node IDs value are of base 16 and the name space size is 4294967295( which is a decimal conversion of 0xffff ffff). Log(4294967295)base_16 is 8. Hence the maximum number of hops that might happen to reach the destination is 8.
We have run for 10000 nodes and we have observed that the above condition is satisfied since the maximum hop that happend for our network of size 10000 is 6.

##### Node Join: Code and explaination

When a new node is created, it populates it own routing table and then from the created routing table, it sends out the update requests to the nodes present in its routing table. The nodes that have received this request will update their routing table accordingly.


	
###### Tested for maximum number of nodes:

NO OF NODES  	NO OF REQUESTS PER NODE 	 	 Maximum Hop        Time Taken
-----------   	-----------------------			------------	    ----------
1000					100							4					53 sec
5000					100							4					19 min			   
10000			   		5							6                   83 min