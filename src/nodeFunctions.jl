"""

	classes(node) -> classlabels::Vector{Int}

Returns a list of class labels the Node is associated with.

##### Parameters:
* `node::ProductNode`: node to be evaluated
"""
function classes(node::ProductNode)

	classNodes = Vector{Int}(0)

  for classNode in filter(c -> isa(c, ClassIndicatorNode), node.children)
    push!(classNodes, classNode.class)
  end

  for parent in node.parents
    classNodes = cat(1, classNodes, classes(parent))
  end

	return unique(classNodes)
end

"""

	classes(node) -> classlabels::Vector{Int}

Returns a list of class labels the Node is associated with.

##### Parameters:
* `node::SPNNode`: Node to be evaluated.
"""
function classes(node::SPNNode)

  classNodes = Vector{Int}(0)

  for parent in node.parents
    classNodes = cat(1, classNodes, classes(parent))
  end

	return unique(classNodes)
end

"""

	children(node) -> children::SPNNode[]

Returns the children of an internal node.

##### Parameters:
* `node::Node`: Internal SPN node to be evaluated.
"""
function children(node::Node)
	node.children
end

"""

	parents(node) -> parents::SPNNode[]

Returns the parents of an SPN node.

##### Parameters:
* `node::SPNNode`: SPN node to be evaluated.
"""
function parents(node::SPNNode)
	node.parents
end

"""

	normalize!(S)

Localy normalize the weights of a SPN using Algorithm 1 from Peharz et al.

##### Parameters:
* `node::SumNode`: Sum Product Network

##### Optional Parameters:
* `ϵ::Float64`: Lower bound to ensure we don't devide by zero. (default 1e-10)
"""
function normalize!(S::SumNode; ϵ = 1e-10)

	nodes = order(S)
	αp = ones(length(nodes))

	for (nid, node) in enumerate(nodes)

		if isa(node, Leaf)
			continue
		end

		α = 0.0

		if isa(node, SumNode)
			α = sum(node.weights)

			if α < ϵ
				α = ϵ
			end
			node.weights[:] ./= α
			node.weights[node.weights .< ϵ] = ϵ

		elseif isa(node, ProductNode)
			α = αp[nid]
			αp[nid] = 1
		end

		for fnode in parents(node)

			if isa(fnode, SumNode)
				id = findfirst(children(fnode) .== node)
				@assert id > 0
				fnode.weights[id] = fnode.weights[id] * α
			elseif isa(fnode, ProductNode)
				id = findfirst(nodes .== fnode)
				if id == 0
					println("parent of the following node not found! ", nid)
				end
				@assert id > 0
				αp[id] = α * αp[id]
			end

		end

	end


end

"""

	normalizeNode!(node) -> parents::SPNNode[]

Normalize the weights of a sum node in place.

##### Parameters:
* `node::SumNode`: Sum node to be normnalized.

##### Optional Parameters:
* `ϵ::Float64`: Additional noise to ensure we don't devide by zero. (default 1e-8)
"""
function normalizeNode!(node::SumNode; ϵ = 1e-8)
  node.weights /= sum(node.weights) + ϵ
  node
end

@doc doc"""
Add a node to a sum node with random weight in place.
add!(node::SumNode, child::SPNNode) -> SumNode
""" ->
function add!(parent::SumNode, child::SPNNode)
  if parent.isFilter
    add!(parent, child, 1e-6)
  else
    add!(parent, child, rand())
  end
end

@doc doc"""
Add a node to a sum node with given weight in place.
add!(node::SumNode, child::SPNNode, weight::Float64) -> SumNode
""" ->
function add!(parent::SumNode, child::SPNNode, weight::Float64)
	if !(child in parent.children)
	  push!(parent.children, child)
	  push!(parent.weights, weight)
	  push!(child.parents, parent)
	end
end

@doc doc"""
Add a node to a product node in place.
add!(node::ProductNode, child::SPNNode) -> ProductNode
""" ->
function add!(parent::ProductNode, child::SPNNode)
	if !(child in parent.children)
	  push!(parent.children, child)
	  push!(child.parents, parent)
	end
end

@doc doc"""
Remove a node from the children list of a sum node in place.
remove!(node::SumNode, index::Int) -> SumNode
""" ->
function remove!(parent::SumNode, index::Int)
	pid = findfirst(parent .== parent.children[index].parents)

	deleteat!(parent.children[index].parents, pid)

	deleteat!(parent.children, index)
  deleteat!(parent.weights, index)

  parent
end

@doc doc"""
Remove a node from the children list of a product node in place.
remove!(node::ProductNode, index::Int) -> ProductNode
""" ->
function remove!(parent::ProductNode, index::Int)
	pid = findfirst(parent .== parent.children[index].parents)

	deleteat!(parent.children[index].parents, pid)
  deleteat!(parent.children, index)

  parent
end


@doc doc"""
Type definition for topological ordering.
Naming could be improved.
""" ->
type SPNMarking
  ordering::Array{SPNNode}
  unmarked::Array{SPNNode}
end

@doc doc"""
Compute topological order of SPN using Tarjan's algoritm.
order(spn::Node) -> SPNNode[] in topological order
""" ->
function order(root::Node)

    function visit!(node::SPNNode, data::SPNMarking)

        if node in data.unmarked

            if isa(node, Node)
                for n in node.children
                    data = visit!(n, data)
                end
            end

            idx = findfirst(data.unmarked, node)
            splice!(data.unmarked, idx)
            push!(data.ordering, node)
        end

        data
    end

    marking = SPNMarking(Array{SPNNode}(0), Array{SPNNode}(0))
    flat!(marking.unmarked, root)

    while(Base.length(marking.unmarked) > 0)
        n = marking.unmarked[end]

        visit!(n, marking)

    end

    marking.ordering
end

"Recursively get number of children including children of children..."
function deeplength(node::SPNNode)

    if isa(node, Leaf)
        return 1
    else
				if Base.length(node.children) > 0
        	return sum([deeplength(child) for child in node.children])
				else
					return 0
				end
    end

end

function length(node::SPNNode)

    if isa(node, Node)
        return Base.length(node.children)
    else
        return 0
    end

end

function flat!(nodes::Array{SPNNode}, node::SPNNode)
    if isa(node, Node)
        for n in node.children
            flat!(nodes, n)
        end
    end

    if !(node in nodes)
        push!(nodes, node)
    end

    nodes
end

"""

	llh(S, data) -> logprobvals::Vector{T}

"""
function llh{T<:Real}(S::Node, data::AbstractArray{T})
    # get topological order
    nodes = order(S)

		maxId = maximum(Int[node.id for node in nodes])
    llhval = Matrix{Float64}(size(data, 1), maxId)

    for node in nodes
        eval!(node, data, llhval)
    end

    return llhval[:, S.id]
end

"""
Evaluate Sum-Node on data.
This function updates the llh of the data under the model.
"""
function filterEval!{T<:Real}(node::SumNode, data::AbstractArray{T}, llhvals::AbstractArray{Float64}, id2index::Function)
  for i = 1:length(node)
    BLAS.axpy!(node.weights[i], sub(llhvals, :, id2index(node.children[i].id)), sub(llhvals, :, id2index(node.id)))
  end
end

function sumEval!{T<:Real}(node::SumNode, data::AbstractArray{T}, llhvals::AbstractArray{Float64}, id2index::Function)
  cids = Int[id2index(child.id) for child in children(node)]

	N = size(data, 1)

	for ii in 1:N
  	llhvals[ii, id2index(node.id)] = logsumexp(vec(llhvals[ii, cids]) + log(node.weights))# .- log(sum(node.weights))
	end

end

function eval!{T<:Real}(node::SumNode, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
		if node.isFilter
      filterEval!(node, data, llhvals, id2index)
    else
      sumEval!(node, data, llhvals, id2index)
		end
end

"""
Evaluate Product-Node on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real}(node::ProductNode, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
	cids = Int[id2index(child.id) for child in children(node)]
	llhvals[:, id2index(node.id)] = sum(sub(llhvals, :, cids), 2)
end

"""
Evaluate ClassIndicatorNode on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real}(node::ClassIndicatorNode, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
  @inbounds llhvals[:, id2index(node.id)] = log( convert(Vector{Int}, data[:,node.scope] .== node.class) )
	@inbounds llhvals[isnan(data[:,node.scope]), id2index(node.id)] = 0.0
end

"""
Evaluate UnivariateFeatureNode on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real}(node::UnivariateFeatureNode, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
	if node.bias
    @inbounds llhvals[:, id2index(node.id)] = zeros(size(data, 1))
  else
    @inbounds llhvals[:, id2index(node.id)] = data[:, node.scope]
  end
end

"""
Evaluate NormalDistributionNode on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real}(node::NormalDistributionNode, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
	for i in 1:size(llhvals, 1)
		@inbounds llhvals[i, id2index(node.id)] = normlogpdf(node.μ, node.σ, data[i, node.scope]) - node.logz
	end
end

"""
Evaluate UnivariateNode on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real, U}(node::UnivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
	@inbounds llhvals[:, id2index(node.id)] = logpdf(node.dist, data[:, node.scope]) - logpdf(node.dist, mean(node.dist))
end

function eval!{T<:Real, U<:ConjugatePostDistribution}(node::UnivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
	@inbounds llhvals[:, id2index(node.id)] = logpred(node.dist, data[:, node.scope])
end

"""
Evaluate MultivariateNode on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real, U}(node::MultivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
  @inbounds llhvals[:, id2index(node.id)] = logpdf(node.dist, data[:, node.scope]')
end

function eval!{T<:Real, U<:ConjugatePostDistribution}(node::MultivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
  @inbounds llhvals[:, id2index(node.id)] = logpred(node.dist, data[:, node.scope])
end
