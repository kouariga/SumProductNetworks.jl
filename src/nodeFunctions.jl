export updateCids!, classes, children, parents, length, add!, remove!, normalize!, llh

function updateCids!(node::Node)
    node.cids = Int[child.id for child in children(node)]
end


"""

classes(node) -> classlabels::Vector{Int}

Returns a list of class labels the Node is associated with.

##### Parameters:
* `node::FiniteProductNode`: node to be evaluated
"""
function classes(node::FiniteProductNode)

    classNodes = Vector{Int}(0)

    for classNode in filter(c -> isa(c, IndicatorNode), node.children)
        push!(classNodes, classNode.value)
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
* `node::FiniteSumNode`: Sum Product Network

##### Optional Parameters:
* `ϵ::Float64`: Lower bound to ensure we don't devide by zero. (default 1e-10)
"""
function normalize!(S::Node; ϵ = 1e-10)

    nodes = order(S)
    αp = ones(length(nodes))

    for (nid, node) in enumerate(nodes)

        if isa(node, Leaf)
            continue
        end

        α = 0.0

        if isa(node, FiniteSumNode)
            α = sum(exp.(node.logweights))

            if α < ϵ
                α = ϵ
            end
            node.logweights[:] .-= log(α)
            node.logweights[exp.(node.logweights) .< ϵ] = ϵ

        elseif isa(node, FiniteProductNode)
            α = αp[nid]
            αp[nid] = 1
        end

        for fnode in parents(node)

            if isa(fnode, FiniteSumNode)
                id = findfirst(children(fnode) .== node)
                @assert id > 0
                fnode.logweights[id] = fnode.logweights[id] + log(α)
            elseif isa(fnode, FiniteProductNode)
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
* `node::FiniteSumNode`: Sum node to be normnalized.

##### Optional Parameters:
* `ϵ::Float64`: Additional noise to ensure we don't devide by zero. (default 1e-8)
"""
function normalizeNode!(node::FiniteSumNode; ϵ = 1e-8)
    node.logweights -= logsumexp(node.logweights)
    node
end

"""
Add a node to a finite sum node with given weight in place.
add!(node::FiniteSumNode, child::SPNNode, weight<:Real)
"""
function add!(parent::FiniteSumNode, child::SPNNode, logweight::T) where T <: Real
    if !(child in parent.children)
        push!(parent.children, child)
        push!(parent.logweights, logweight)
        push!(child.parents, parent)
    end
end

"""
Add a node to an infinite sum node with given weight in place.
add!(node::InfiniteSumNode, child::SPNNode, sticklength<:Real)
"""
function add!(parent::InfiniteSumNode, child::SPNNode, logstick::T) where T <: Real
    if !(child in parent.children)
        push!(parent.children, child)
        push!(parent.logπ, logstick)
	parent.πremain = max(0.f0, parent.πremain - exp(logstick))
        push!(child.parents, parent)
    end
end

"""
Add a node to a finite product node in place.
add!(node::FiniteProductNode, child::SPNNode) -> ProductNode
"""
function add!(parent::FiniteProductNode, child::SPNNode)
    if !(child in parent.children)
        push!(parent.children, child)
        push!(child.parents, parent)
    end
end

"""
Add a node to a finite product node in place.
add!(node::FiniteProductNode, child::SPNNode) -> ProductNode
"""
function add!(parent::FiniteAugmentedProductNode, child::SPNNode, logomega::Float32)
    if !(child in parent.children)
        push!(parent.children, child)
        push!(child.parents, parent)
        push!(parent.logomega, logomega)
    end
end


"""
Add a node to an infinite product node in place.
add!(node::InfiniteProductNode, child::SPNNode, sticklength<:Real)
"""
function add!(parent::InfiniteProductNode, child::SPNNode, logstick::T) where T <: Real
    if !(child in parent.children)
        push!(parent.children, child)
        push!(parent.logω, logstick)
	parent.ωremain = max(0.f0, parent.ωremain - exp(logstick))
        push!(child.parents, parent)
    end
end

"""
Remove a node from the children list of a sum node in place.
remove!(node::FiniteSumNode, index::Int)
"""
function remove!(parent::FiniteSumNode, index::Int)
    pid = findfirst(parent .== parent.children[index].parents)
    @assert pid > 0 "Could not find parent ($(node.id)) in list of parents ($(parent.children[index].parents))!"
    deleteat!(parent.children[index].parents, pid)
    deleteat!(parent.children, index)
    deleteat!(parent.logweights, index)
end

"""
Remove a node from the children list of an infinite sum node in place.
remove!(node::InfiniteSumNode, index::Int)
"""
function remove!(parent::InfiniteSumNode, index::Int)
    pid = findfirst(parent .== parent.children[index].parents)
    @assert pid > 0 "Could not find parent ($(node.id)) in list of parents ($(parent.children[index].parents))!"
    deleteat!(parent.children[index].parents, pid)
    deleteat!(parent.children, index)
    parent.πremain = min(1.f0, parent.πremain + exp(parent.logπ[index]))
    deleteat!(parent.logπ, index)
end

"""
Remove a node from the children list of a product node in place.
remove!(node::FiniteProductNode, index::Int)
"""
function remove!(parent::FiniteProductNode, index::Int)
    pid = findfirst(parent .== parent.children[index].parents)
    @assert pid > 0 "Could not find parent ($(node.id)) in list of parents ($(parent.children[index].parents))!"
    deleteat!(parent.children[index].parents, pid)
    deleteat!(parent.children, index)
end

"""
Remove a node from the children list of an infinite product node in place.
remove!(node::InfiniteProductNode, index::Int)
"""
function remove!(parent::InfiniteProductNode, index::Int)
    pid = findfirst(parent .== parent.children[index].parents)
    @assert pid > 0 "Could not find parent ($(node.id)) in list of parents ($(parent.children[index].parents))!"
    deleteat!(parent.children[index].parents, pid)
    deleteat!(parent.children, index)
    parent.ωremain = min(1.f0, parent.ωremain + exp(parent.logω[index]))
    deleteat!(parent.logω, index)
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

"""

llh(S, data) -> logprobvals::Vector{T}

"""
function llh(S::Node, data, nodes, maxID)
    llhval = Matrix{Float32}(size(data, 1), maxID)

    fill!(llhval, 0.f32)

    for node in nodes
        eval!(node, data, llhval)
    end

    return llhval[:, S.id]
end

function llh(S::Node, data, nodes)
    maxID = maximum(node.id for node in nodes)
    return llh(S, data, nodes, maxID)
end

function llh(S::Node, data)
    nodes = order(S)
    return llh(S, data, nodes)
end


"""
Evaluate Sum-Node on data.
This function updates the llh of the data under the model.
"""
function eval!(node::FiniteSumNode, data, llhvals)
    if isempty(node.scope)
        @inbounds llhvals[:,node.id] = 0.f32
    else
        @simd for ii in 1:size(llhvals, 1)
            @inbounds llhvals[ii,node.id] = logsumexp(view(llhvals, ii, node.cids) + node.logweights)
        end
    end
end

"""
Evaluate infinite Sum-Node on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real}(node::InfiniteSumNode, data::AbstractMatrix{T}, llhvals::SharedArray{B} where B <: AbstractFloat)

    if isempty(node.scope)
        @inbounds llhvals[:, node.id] = 0.f32
    else

        cids = Int[child.id for child in children(node)]
        logw = node.logπ
        z = logsumexp(node.logπ)
        @simd for ii in 1:size(llhvals, 1)
            @inbounds llhvals[:,node.id] = logsumexp(view(llhvals, ii, cids) + logw) - z
        end
    end
end

"""
Evaluate Product-Node on data.
This function updates the llh of the data under the model.
"""
function eval!(node::ProductNode, data, llhvals)
    if isempty(node.scope)
        @inbounds llhvals[:, node.id] = 0.f32
    else
        @inbounds for ii in 1:size(llhvals, 1)
            for child in filter(c -> c.scope ⊆ node.scope, children(node))
                llhvals[ii, node.id] += llhvals[ii, child.id]
            end
        end
    end
end

"""
Evaluate IndicatorNode on data.
This function updates the llh of the data under the model.
"""
function eval!(node::IndicatorNode, data, llhvals)
    @simd for ii in 1:size(data, 1)
        @inbounds llhvals[ii, node.id] = data[ii,node.scope] == node.value ? 0 : -Inf32
    end
    # @assert !any(isnan(view(llhvals, 1:size(data, 1), nid))) "result computed by indicator node: $(node.id) contains NaN's!"
end

"""
Evaluate NormalDistributionNode on data.
This function updates the llh of the data under the model.
"""
function eval!(node::NormalDistributionNode, data::AbstractMatrix{Float64}, llhvals::SharedArray{A} where A <: AbstractFloat)
    nid = id2index(node.id)
    @simd for i in 1:size(data, 1)
        @inbounds llhvals[i, nid] = isnan(data[i,node.scope]) ? 0.0 : normlogpdf(node.μ, node.σ, data[i, node.scope])
    end

    # @assert !any(isnan.(view(llhvals, 1:size(data, 1), nid))) "result computed by normal distribution node: $(node.id) with μ: $(node.μ) and σ: $(node.σ) contains NaN's!"
end

"""
Evaluate UnivariateNode on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real, U}(node::UnivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
    @inbounds llhvals[:, id2index(node.id)] = logpdf(node.dist, data[:, node.scope])
    # @assert !any(isnan.(view(llhvals, 1:size(data, 1), id2index(node.id)))) "result computed by univariate distribution node: $(node.id) with distribution: $(node.dist) contains NaN's!"
end

"""
Evaluate MultivariateNode on data.
This function updates the llh of the data under the model.
"""
function eval!{T<:Real, U}(node::MultivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
    @inbounds llhvals[:, id2index(node.id)] = logpdf(node.dist, data[:, node.scope]')
    # @assert !any(isnan.(view(llhvals, 1:size(data, 1), id2index(node.id)))) "result computed by multivariate distribution node: $(node.id) with distribution: $(node.dist) contains NaN's!"
end

function eval!{T<:Real, U<:ConjugatePostDistribution}(node::UnivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
    @inbounds llhvals[:, id2index(node.id)] = logpostpred(node.dist, data[:, node.scope])
end

function eval!{T<:Real, U<:ConjugatePostDistribution}(node::MultivariateNode{U}, data::AbstractArray{T}, llhvals::AbstractArray{Float64}; id2index::Function = (id) -> id)
    @inbounds llhvals[:, id2index(node.id)] = logpostpred(node.dist, data[:, node.scope])
end
