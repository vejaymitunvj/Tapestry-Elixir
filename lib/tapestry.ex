################################# START OF APP ######################################
################################# START OF TAPESTRY ######################################
#####################################################################################
##                                                                                 ##
## Description: The application module which accepts the commandline arguments     ##
##              and starts the supervisor                                          ##
##                                                                                 ##
##                                                                                 ##
##                                                                                 ##
##                                                                                 ##
#####################################################################################

defmodule Tapestry do
  def main(argv) do
    input = argv

    num_string = input |> Enum.at(0)
    {num_nodes, ""} = Integer.parse(num_string, 10)

    req_string = input |> Enum.at(1)
    {num_requests, ""} = Integer.parse(req_string, 10)
#    IO.puts("REQUIRED # of NODES IN NETWORK = #{inspect num_nodes}")
#    IO.puts("# OF REQUESTS EACH NODE MUST SEND PER SECOND = #{inspect num_requests}")
    NodeMonitor.start_link([num_nodes, num_requests])
  end
end

##### START OF ROUTING TABLE CREATING WITH DISTANCE CALCULATION #####
defmodule Routing do
  def createRoutingTable(shaList, nodeID) do
    shaList = shaList -- [nodeID]
    #    IO.inspect(nodeID)
    {nodeVal, ""} = Integer.parse(nodeID, 16)
    column = Enum.map(0..15, fn x -> Integer.to_string(x, 16) |> String.downcase() end)

    Map.new(1..8, fn level ->
      baseVal =
        Map.new(column, fn base ->
          if level == 1 do
            lvlVal =
              Enum.filter(shaList, fn x ->
                String.at(x, 0) == String.downcase(base) and
                  String.at(x, 0) !== String.at(nodeID, 0)
              end)

            if lvlVal !== [] do
              randVal =
                Enum.min_by(lvlVal, fn x ->
                  {valx, ""} = Integer.parse(x, 16)
                  abs(nodeVal - valx)
                end)

              {base, randVal}
            else
              {base, nil}
            end
          else
            lvlValnxt =
              Enum.filter(shaList, fn x ->
                String.slice(x, 0..(level - 1)) ==
                  String.slice(nodeID, 0..(level - 2)) <> String.downcase(base)
              end)

            if lvlValnxt !== [] do
              randVal =
                Enum.min_by(lvlValnxt, fn x ->
                  {valx, ""} = Integer.parse(x, 16)
                  abs(nodeVal - valx)
                end)

              {base, randVal}
            else
              {base, nil}
            end
          end
        end)

      {level, baseVal}
    end)
  end

  ##### END OF ROUTING TABLE CREATING WITH DISTANCE CALCULATION #####

  ##### START OF SHA 1 LIST CREATION #####
  def shaListGenerator(numOfNodes) do
    Enum.map(1..numOfNodes, fn nodeValue ->
      shaValList =
        :crypto.hash(:sha, "#{nodeValue}")
        |> Base.encode16()
        |> String.downcase()
        |> String.slice(0..7)

      shaValList
    end)
  end

  def shaValue(nodeValue) do
    :crypto.hash(:sha, "#{nodeValue}") |> Base.encode16() |> String.downcase() |> String.slice(0..7)
  end

  ##### END OF SHA 1 LIST CREATION #####
end

################################# END OF TAPESTRY ######################################

################################# START OF NODE MONITOR ######################################
#####################################################################################
##                                                                                 ##
## Description: The application module which accepts the commandline arguments     ##
##              and starts the supervisor                                          ##
##                                                                                 ##
##                                                                                 ##
##                                                                                 ##
##                                                                                 ##
#####################################################################################

defmodule NodeMonitor do
  @moduledoc """
  Documentation for NodeMonitor.
  """

  @doc """
  Network NodeMonitor

  ## Examples
  """

  use GenServer
  @self __MODULE__

  def start_link(argv) do
    GenServer.start_link(__MODULE__, argv, name: @self)
  end

  @impl true
  def init(argv) do
    [num_nodes, num_requests] = argv
    num_nodes = num_nodes - 1 ## We will join the last node
    # Create a table to keep track of stuff
    :ets.new(:record, [:set, :public, :named_table])
    :ets.insert(:record, {"ready_status", %{count: 0, pids: []}})
    :ets.insert(:record, {"config", argv})
    :ets.insert(:record, {"maximum_hop", 0})
    ##### GENERATES SHA-1 lIST FOR GIVEN NODES ######
    sha_list = Routing.shaListGenerator(num_nodes)
    # This is to keep track of how many msg have been successfully delived to the root 
    routed_msg_count =
      sha_list |> Enum.chunk_every(1) |> Map.new(fn [k] -> {k, %{count: 0, max_hop: 0}} end)
    
    :ets.insert(:record, {"sha_list", sha_list})
    :ets.insert(:record, {"routed_msg_count", routed_msg_count})
    GenServer.cast(@self, {:start_nodes, [num_nodes, num_requests]})
    {:ok, argv}
  end

  def route_success(msg) do
    Process.send_after(@self, {:route_success, msg}, 0)
  end

  def done(node_id) do
    GenServer.cast(@self, {:done, node_id})
  end

  @impl true
  def handle_info({:route_success, msg}, state) do
    {src_node_id, _dst_node_id, hop_count} = msg
    [{_, routed_msg_count}] = :ets.lookup(:record, "routed_msg_count")
    [{_, old_maximum_hop}] = :ets.lookup(:record, "maximum_hop")
    map = Map.get(routed_msg_count, src_node_id)
    map = if(map == nil) do
      Map.put(routed_msg_count, src_node_id, %{count: 0, max_hop: 0})
      %{count: 0, max_hop: 0}
    else
      map
    end
    prev_count = Map.get(map, :count)
    prev_max_hop = Map.get(map, :max_hop)
    current_count = prev_count + 1
    current_max_hop = max(prev_max_hop, hop_count)
    map = Map.put(map, :count, current_count)
    map = Map.put(map, :max_hop, current_max_hop)
    current_maximum_hop = max(old_maximum_hop, current_max_hop)
    routed_msg_count = Map.put(routed_msg_count, src_node_id, map)
    :ets.insert(:record, {"maximum_hop", current_maximum_hop})
    :ets.insert(:record, {"routed_msg_count", routed_msg_count})
    {:noreply, state}
  end

  def node_spawn(batch_list) do
    len = length(batch_list)
    batch_list = if(len < 20) do
      buffer = Enum.map(Enum.to_list(1..(20 - len)), fn _x -> [] end)
      batch_list ++ buffer ## To prevent task error and multiple checks.
    else
      batch_list
    end
    task1 = Task.async(fn -> Enum.each(Enum.at(batch_list, 0), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task2 = Task.async(fn -> Enum.each(Enum.at(batch_list, 1), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task3 = Task.async(fn -> Enum.each(Enum.at(batch_list, 2), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task4 = Task.async(fn -> Enum.each(Enum.at(batch_list, 3), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task5 = Task.async(fn -> Enum.each(Enum.at(batch_list, 4), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task6 = Task.async(fn -> Enum.each(Enum.at(batch_list, 5), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task7 = Task.async(fn -> Enum.each(Enum.at(batch_list, 6), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task8 = Task.async(fn -> Enum.each(Enum.at(batch_list, 7), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task9 = Task.async(fn -> Enum.each(Enum.at(batch_list, 8), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task10 = Task.async(fn -> Enum.each(Enum.at(batch_list, 9), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task11 = Task.async(fn -> Enum.each(Enum.at(batch_list, 10), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task12 = Task.async(fn -> Enum.each(Enum.at(batch_list, 11), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task13 = Task.async(fn -> Enum.each(Enum.at(batch_list, 12), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task14 = Task.async(fn -> Enum.each(Enum.at(batch_list, 13), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task15 = Task.async(fn -> Enum.each(Enum.at(batch_list, 14), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task16 = Task.async(fn -> Enum.each(Enum.at(batch_list, 15), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task17 = Task.async(fn -> Enum.each(Enum.at(batch_list, 16), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task18 = Task.async(fn -> Enum.each(Enum.at(batch_list, 17), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task19 = Task.async(fn -> Enum.each(Enum.at(batch_list, 18), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    task20 = Task.async(fn -> Enum.each(Enum.at(batch_list, 19), fn node_id -> if(node_id != nil, do: Nodes.start_link({node_id, false}) ) end) end)   
    Task.await(task1, :infinity)
    Task.await(task2, :infinity)
    Task.await(task3, :infinity)
    Task.await(task4, :infinity)
    Task.await(task5, :infinity)
    Task.await(task6, :infinity)
    Task.await(task7, :infinity)
    Task.await(task8, :infinity)
    Task.await(task9, :infinity)
    Task.await(task10, :infinity)
    Task.await(task11, :infinity)
    Task.await(task12, :infinity)
    Task.await(task13, :infinity)
    Task.await(task14, :infinity)
    Task.await(task15, :infinity)
    Task.await(task16, :infinity)
    Task.await(task17, :infinity)
    Task.await(task18, :infinity)
    Task.await(task19, :infinity)
    Task.await(task20, :infinity)
  end

  def start_trigger() do
    [{_, sha_list}] = :ets.lookup(:record, "sha_list")
    [{_, config}] = :ets.lookup(:record, "config")
    [_num_nodes, num_requests] = config
    ### TRIGGER NODES ###
#    start_time = System.monotonic_time(:millisecond)
    Enum.each(sha_list, fn x -> GenServer.cast(:"node_#{x}", {:trigger, num_requests}) end)
#    end_time2 = System.monotonic_time(:millisecond)
#    diff2 = end_time2 - start_time
#    IO.puts("NODE TRIGGER COMPLETED. TRIGGER TIME = #{inspect diff2} millisecond")
  end

  @impl true
  def handle_cast({:start_nodes, argv}, _state) do
    [num_nodes, num_requests] = argv
    [{_, sha_list}] = :ets.lookup(:record, "sha_list")
#    IO.puts("#{inspect num_nodes} NODE CREATION STARTED")
#    start_time = System.monotonic_time(:millisecond)
    # CURRENTLY WE ARE CREATING N nodes
    batch_size = ceil((num_nodes) * 0.05) #5% split
    batch_list = Enum.chunk_every(sha_list, batch_size)

    ## LET's DEPLOY A NETWORK OF N-1 NODES
    node_spawn(batch_list)
#    end_time1 = System.monotonic_time(:millisecond)

    #########################################################
    ## LET'S CREATE ANOTHER NODE AND MAKE IT JOIN OUR NETWORK
    num_nodes = num_nodes + 1
    IO.puts("JOINING THE LAST NODE. TOTAL # OF NODES IN THE NETWORK NOW = #{inspect num_nodes}")
    node_val = Routing.shaValue(num_nodes) ## LAST NODE ID VALUE
    sha_list_new = sha_list ++ [node_val]  ## ADDING OUR NODE VALUE TO THE LIST
    :ets.insert(:record, {"sha_list", sha_list_new})
    Nodes.start_link({node_val, true})
#    IO.puts("NEW SHA LIST #{inspect sha_list_new} OLD: #{inspect sha_list}")
    ###############################################
#    end_time2 = System.monotonic_time(:millisecond)
#    diff1 = end_time1 - start_time
#    diff2 = end_time2 - start_time
#    IO.puts("NODE CREATION. SPAWN TIME = #{inspect diff1} millisecond")
    
    state = [sha_list_new, num_requests, []]
    {:noreply, state}
  end

  @impl true
  def handle_cast({:done, node_id}, state) do
    [sha_list, num_requests, done_list] = state
    done_list = done_list ++ [node_id]

    if length(sha_list) == length(done_list) do
      [{_, maximum_hop}] = :ets.lookup(:record, "maximum_hop")
      IO.puts("ALL NODES HAVE COMPLETED #{inspect num_requests} REQUESTS SUCCESSFULLY")
      IO.puts("MAXIMUM # OF HOPS TO REACH THE ROOT NODE = #{inspect maximum_hop}")
      System.halt(0)
    end

    state = [sha_list, num_requests, done_list]
    {:noreply, state}
  end
end

################################# END OF NODE MONITOR ######################################
################################# START OF NODE ######################################
#####################################################################################
##                                                                                 ##
## Description: The application module which accepts the commandline arguments     ##
##              and starts the supervisor                                          ##
##                                                                                 ##
##                                                                                 ##
##                                                                                 ##
##                                                                                 ##
#####################################################################################

defmodule Nodes do
  @moduledoc """
  Documentation for Node.
  """

  @doc """
  Network Node

  ## Examples
  """
  use GenServer

  def start_link(argv) do
    {num, _join} = argv
    GenServer.start(__MODULE__, argv, name: :"node_#{num}")
  end

  @impl true
  def init(argv) do
    {node_id, join} = argv
    ### POPULATE TABLE ###
    [{_, sha_list}] = :ets.lookup(:record, "sha_list")
    table = Routing.createRoutingTable(sha_list, node_id)
    if (join == true) do
      ## AFTER UPDATING SELF INFORM THEM ALL
      i = Enum.to_list(1..8)
      j = Enum.to_list(0..15)
      j = Enum.map(j, fn x -> Integer.to_string(x, 16) |> String.downcase() end)
      node_list = Enum.filter(Enum.flat_map(i, fn x -> Enum.map(j, fn y -> table[x][y]  end)end), fn x -> x != nil end)
#      IO.puts("NEW NODE #{inspect node_id} table: #{inspect table} UPDATE BATCH LIST #{inspect node_list}")
      update_others(node_list, node_id)
    end
    num_request = 0
    state = {node_id, num_request, table}
    {:ok, state}
  end

  def update_others(node_list, _node_id) do
    batch_list = Enum.chunk_every(node_list, ceil(length(node_list)*0.2)) # 20% task split
    len = length(batch_list)
    batch_list = if(len < 5) do
      buffer = Enum.map(Enum.to_list(1..(5 - len)), fn _x -> [] end)
      batch_list ++ buffer ## To prevent task error and multiple checks.
    else
      batch_list
    end
#    IO.puts("UPDATING NEIGHBORS")
    task1 = Task.async(fn -> Enum.each(Enum.at(batch_list, 0), fn node_id -> if(node_id != nil, do: GenServer.call(:"node_#{node_id}", :update_table) ) end) end)
    task2 = Task.async(fn -> Enum.each(Enum.at(batch_list, 1), fn node_id -> if(node_id != nil, do: GenServer.call(:"node_#{node_id}", :update_table) ) end) end)
    task3 = Task.async(fn -> Enum.each(Enum.at(batch_list, 2), fn node_id -> if(node_id != nil, do: GenServer.call(:"node_#{node_id}", :update_table) ) end) end)
    task4 = Task.async(fn -> Enum.each(Enum.at(batch_list, 3), fn node_id -> if(node_id != nil, do: GenServer.call(:"node_#{node_id}", :update_table) ) end) end)
    task5 = Task.async(fn -> Enum.each(Enum.at(batch_list, 4), fn node_id -> if(node_id != nil, do: GenServer.call(:"node_#{node_id}", :update_table) ) end) end)
    Task.await(task1, :infinity)
    Task.await(task2, :infinity)
    Task.await(task3, :infinity)
    Task.await(task4, :infinity)
    Task.await(task5, :infinity)
#    IO.puts("NEIGHBORS UPDATED")
    ## WE ARE RANDOMLY SELECTING AND SENDING REQUEST. TO PREVENT RACE CONDITION LET'S UPDATE THE POOL FROM WHICH RANDOM SELECTION HAPPENS AFTER ALL NODES ARE UPDATED
    NodeMonitor.start_trigger() 
  end

  @impl true
  def handle_info(:periodic_request, state) do
    {node_id, num_request_old, table} = state

    num_request_new =
      if num_request_old > 0 do
        ### BUILD A NEW MESSAGE ###
        ### SELECT A RANDOM NODE TO SEND MESSAGE TO ###
        [{_, sha_list}] = :ets.lookup(:record, "sha_list")
        dst_node_id = Enum.random(sha_list)
        src_node_id = node_id
        hop_count = 0
        msg = {src_node_id, dst_node_id, hop_count}
        Process.send_after(self(), {:rcv_message, msg}, 0)
        Process.send_after(self(), :periodic_request, 100)
        num_request_old - 1
      else
        # DO NOTHING #
        NodeMonitor.done(node_id)
        num_request_old
      end

    state = {node_id, num_request_new, table}
    {:noreply, state}
  end

  @impl true
  def handle_info({:rcv_message, msg}, state) do
    {node_id, _num_request_old, table} = state
    {src_node_id, dst_node_id, hop_count} = msg

    if dst_node_id != node_id do
      # FIND THE PREFIX VALUE MATCHED #
      match_len =
        Enum.find_index(0..String.length(node_id), fn i ->
          String.at(node_id, i) != String.at(dst_node_id, i)
        end)

      chk_lvl = max(match_len, hop_count) + 1
      i_char = String.at(dst_node_id, chk_lvl - 1)
      # FIND NEXT NODE TO SEND
      nxt_node = table[chk_lvl][i_char]
      if nxt_node != nil do
        hop_count = hop_count + 1
        msg = {src_node_id, dst_node_id, hop_count}
        # GenServer.call(:"node_#{nxt_node}", {:rcv_message, msg})
        Process.send_after(:"node_#{nxt_node}", {:rcv_message, msg}, 0)
      else
       IO.puts("DEBUG: NEXT NODE NOT FOUND NODE: #{inspect node_id} MSG: #{inspect msg} table: #{inspect table}, ROUTING TO THE NEAREST NODE")
      end
    else
      # UPDATE THE MESSAGE HAS REACHED THE DEST #
#      IO.puts("REACHED DESTINATION #{inspect(msg)}")
      NodeMonitor.route_success(msg)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:update_table, _from, state) do
        ### POPULATE TABLE ###
    [{_, sha_list}] = :ets.lookup(:record, "sha_list")
    {node_id, num_request, _table} = state
#    IO.puts("NODE #{inspect node_id} getting updated")
    table = Routing.createRoutingTable(sha_list, node_id)
#    IO.puts("NODE #{inspect node_id} sha_list: #{inspect sha_list} TABLE #{inspect table}")

    state = {node_id, num_request, table}
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:trigger, num_request}, state) do
    ### START THE MESSAGES ###
    {node_id, _num_request_old, table} = state
    # We are starting with one request now
    state = {node_id, num_request, table}

    ### SELECT A RANDOM NODE TO SEND MESSAGE TO ###
    [{_, sha_list}] = :ets.lookup(:record, "sha_list")
    dst_node_id = Enum.random(sha_list)
    src_node_id = node_id
    hop_count = 0
    msg = {src_node_id, dst_node_id, hop_count}
    Process.send_after(self(), {:rcv_message, msg}, 0)
    Process.send_after(self(), :periodic_request, 100)
    {:noreply, state}
  end
end

################################# END OF NODE ######################################
################################# END OF APP ######################################
