### A Pluto.jl notebook ###
# v0.14.8

using Markdown
using InteractiveUtils

# ╔═╡ 1598cc4c-ce91-11eb-22be-e95b0eee4d58
using FastAI

# ╔═╡ a005a1f9-5b34-471f-816d-4f4821490256
begin
	using FastAI.Datasets
	using FastAI.Datasets: datasetpath, loadtaskdata
	using FastAI.Datasets: FileDataset
	using FastAI.Datasets: loadfile, filename
	using FastAI: DLPipelines
end

# ╔═╡ 7221e043-a0e6-48d1-9fdf-3e935110bb7f
begin
	using Flux
	using Flux: onehotbatch, onecold, crossentropy, throttle
	using Base.Iterators: repeated, partition
	using Printf, BSON
	using ImageView
	using ImageIO
	using Plots
end

# ╔═╡ cc0cee1a-b41c-4b06-a4e3-c3c144e609b6
using PlutoUI, Images, DataFrames, DecisionTree, CairoMakie, FluxTraining, QuartzImageIO

# ╔═╡ 81228e80-421c-4bd5-8588-d4cb59fc9f79
using Statistics

# ╔═╡ 7706c0da-e5f9-4950-a492-4bf14b2daee3
begin
	using DataAugmentation
	using Colors: RGB
	using FastAI: IMAGENET_MEANS, IMAGENET_STDS
end

# ╔═╡ 366b0dcb-8d56-4c10-b215-a35505d49300
filedata = FileDataset("/Users/leonardopetrus/Desktop/CHEST_X-RAY")

# ╔═╡ 72d87139-ad8e-42d0-b5f4-cb940901e9d6
filedataTest = FileDataset("/Users/leonardopetrus/Desktop/AIG/chest_xray/chest_xray/test")

# ╔═╡ e882fc6e-de23-4e13-935a-5991b81ad1a7
filedataTrain = FileDataset("/Users/leonardopetrus/Desktop/AIG/chest_xray/chest_xray/train")

# ╔═╡ 2305317a-f08d-45e7-bc2c-e0373ae5eebc
filedataVal = FileDataset("/Users/leonardopetrus/Desktop/AIG/chest_xray/chest_xray/val")

# ╔═╡ 877928c0-f44c-4ff7-b8da-26927db181b3
p = getobs(filedata,6)

# ╔═╡ 16bb4d56-de2d-473b-a24a-38fd17b93750
begin
    gr()
    plot(-10:0.5:10, sigmoid.(-10:0.5:10), label=false, title="sigmoid function", 		lw=2, size=(400, 300), color="Green")
end

# ╔═╡ 36db6774-2600-43fa-b797-3f5d6eb0991c
function resize_and_grayify(directory, im_name, width::Int64, height::Int64)
    resized_gray_img = Gray.(load(directory * "/" * im_name)) |> (x -> imresize(x, width, height))
    try
        save("preprocessed_" * directory * "/" * im_name, resized_gray_img)
    catch e
        if isa(e, SystemError)
            mkdir("preprocessed_" * directory)
            save("preprocessed_" * directory * "/" * im_name, resized_gray_img)
        end
    end
end

# ╔═╡ d91fc110-03bf-4475-ba72-63b9faf54229
function process_images(directory, width::Int64, height::Int64)
    files_list = readdir(directory)
    map(x -> resize_and_grayify(directory, x, width, height),                               files_list)
end

# ╔═╡ 820c67c2-97ca-4339-956d-aee89c8a52d8
test = vcat(filedataTest);

# ╔═╡ 7a1e95dd-f959-4d50-b4b3-bf9a7ccf912a
train = vcat(filedataTrain);

# ╔═╡ 6c3c3c80-3c09-4850-9bf7-aad93526e48e
val = vcat(filedataVal);

# ╔═╡ a6ba9e73-452d-4406-aa9b-c5504531865c
begin
    labels = vcat([0 for _ in 1:length(test)], [1 for _ in 1:length(train)])
    (x_train, y_train), (x_test, y_test) = splitobs(shuffleobs((data, labels)), at =       0.7)
end;

# ╔═╡ 1064638d-fdb2-4e6b-91b1-797811103060
function make_minibatch(X, Y, idxs)
    X_batch = Array{Float32}(undef, size(X[1])..., 1, length(idxs))
    for i in 1:length(idxs)
        X_batch[:, :, :, i] = Float32.(X[idxs[i]])
    end
    Y_batch = onehotbatch(Y[idxs], 0:1)
    return (X_batch, Y_batch)
end

# ╔═╡ 0d414133-5da9-4df5-9ef2-63d3ed07a4ac
begin
    # here we define the train and test sets.
    batchsize = 128
    mb_idxs = partition(1:length(x_train), batchsize)
    train_set = [make_minibatch(x_train, y_train, i) for i in mb_idxs]
    test_set = make_minibatch(x_test, y_test, 1:length(x_test));
end;

# ╔═╡ 69367bfc-7ca9-4a21-96b0-323cd8d826b2


# ╔═╡ 3f69f5b3-28b5-4096-8c15-eec66d1cc277
md"## CNN MODEL: LeNet5"

# ╔═╡ 0c2207dc-51f2-461a-a016-e699c94fbf10
begin
	model = Chain(
	    # First convolution, operating upon a 28x28 image
	    Conv((3, 3), 1=>16, pad=(1,1), relu),
	    MaxPool((2,2)), #maxpooling
	
	    # Second convolution, operating upon a 14x14 image
	    Conv((3, 3), 16=>32, pad=(1,1), relu),
	    MaxPool((2,2)), #maxpooling
	
	    # Third convolution, operating upon a 7x7 image
	    Conv((3, 3), 32=>32,pad=(1,1), relu),
	    MaxPool((2,2)),
		
		Conv((3, 3), 32=>64, pad=(1,1), stride=2, relu),
    	x -> reshape(x, :, size(x, 1)),

	
	    # Reshape 3d tensor into a 2d one, at this point it should be (3, 3, 32, N)
	    # which is where we get the 288 in the `Dense` layer below:
	    x -> reshape(x, :, size(x, 4)),
	    Dense(288, 10),
	
	    # Softmax to get probabilities
	    softmax,
	)
	
	# Load on gpu (if available)
	model = gpu(model);
end

# ╔═╡ 7efe648a-b32d-41fd-81d1-8ec88406f1af
begin
		# Loss function
		# See: https://github.com/FluxML/model-zoo/blob/master/vision/mnist/conv.jl
		# `loss()` calculates the crossentropy loss between our prediction `y_hat`
		function loss(x, y)
		    # Add some noise to the image
		    # we reduce the risk of overfitting the train sample by doing so:
		    x_aug = x .+ 0.1f0*gpu(randn(eltype(x), size(x)))
		
		    y_hat = model(x_aug)
		    return crossentropy(y_hat, y)
		end
		accuracy(x, y) = mean(onecold(model(x)) .== onecold(y))
		
		# ADAM optimizer
		opt = ADAM(0.005);
	
	
		train_loss = Float64[]
    test_loss = Float64[]
    acc = Float64[]
    ps = Flux.params(model)
    opt = ADAM()
    L(x, y) = Flux.crossentropy(model(x), y)
    L((x,y)) = Flux.crossentropy(model(x), y)
    accuracy(x, y, f) = mean(Flux.onecold(f(x)) .== Flux.onecold(y))
    
    function update_loss!()
        push!(train_loss, mean(L.(train_set)))
        push!(test_loss, mean(L(test_set)))
        push!(acc, accuracy(test_set..., model))
        @printf("train loss = %.2f, test loss = %.2f, accuracy = %.2f\n", train_loss[end], test_loss[end], acc[end])
    end
end

# ╔═╡ b5ecdbeb-59b6-47e0-bf2a-e489baac4f74
@epochs 10 Flux.train!(L, ps, train_set, opt;
               cb = Flux.throttle(update_loss!, 8))

# ╔═╡ a13ca6c7-b165-4907-ab9b-b409426eaa98
begin
    plot(train_loss, xlabel="Iterations", title="Model Training", label="Train loss", lw=2, alpha=0.9)
    plot!(test_loss, label="Test loss", lw=2, alpha=0.9)
    plot!(acc, label="Accuracy", lw=2, alpha=0.9)
end

# ╔═╡ 9bbad557-5cc9-4cac-b1ef-2269f3210c7c
@epochs 5 Flux.train!(L, ps, train_set, opt_2;
               cb = Flux.throttle(update_loss!, 8))

# ╔═╡ b2137bec-d9ae-4c6d-815a-ac1e30440ec6
begin
    plot(train_loss, xlabel="Iterations", title="Model Training", label="Train loss", lw=2, alpha=0.9, legend = :right)
    plot!(test_loss, label="Test loss", lw=2, alpha=0.9)
    plot!(acc, label="Accuracy", lw=2, alpha=0.9)
    vline!([82], lw=2, label=false)
end

# ╔═╡ Cell order:
# ╠═1598cc4c-ce91-11eb-22be-e95b0eee4d58
# ╠═a005a1f9-5b34-471f-816d-4f4821490256
# ╠═7221e043-a0e6-48d1-9fdf-3e935110bb7f
# ╠═cc0cee1a-b41c-4b06-a4e3-c3c144e609b6
# ╠═81228e80-421c-4bd5-8588-d4cb59fc9f79
# ╠═7706c0da-e5f9-4950-a492-4bf14b2daee3
# ╠═366b0dcb-8d56-4c10-b215-a35505d49300
# ╠═72d87139-ad8e-42d0-b5f4-cb940901e9d6
# ╠═e882fc6e-de23-4e13-935a-5991b81ad1a7
# ╠═2305317a-f08d-45e7-bc2c-e0373ae5eebc
# ╠═877928c0-f44c-4ff7-b8da-26927db181b3
# ╠═16bb4d56-de2d-473b-a24a-38fd17b93750
# ╠═36db6774-2600-43fa-b797-3f5d6eb0991c
# ╠═d91fc110-03bf-4475-ba72-63b9faf54229
# ╠═820c67c2-97ca-4339-956d-aee89c8a52d8
# ╠═7a1e95dd-f959-4d50-b4b3-bf9a7ccf912a
# ╠═6c3c3c80-3c09-4850-9bf7-aad93526e48e
# ╠═a6ba9e73-452d-4406-aa9b-c5504531865c
# ╠═1064638d-fdb2-4e6b-91b1-797811103060
# ╠═0d414133-5da9-4df5-9ef2-63d3ed07a4ac
# ╠═69367bfc-7ca9-4a21-96b0-323cd8d826b2
# ╠═3f69f5b3-28b5-4096-8c15-eec66d1cc277
# ╠═0c2207dc-51f2-461a-a016-e699c94fbf10
# ╠═7efe648a-b32d-41fd-81d1-8ec88406f1af
# ╠═b5ecdbeb-59b6-47e0-bf2a-e489baac4f74
# ╠═a13ca6c7-b165-4907-ab9b-b409426eaa98
# ╠═9bbad557-5cc9-4cac-b1ef-2269f3210c7c
# ╠═b2137bec-d9ae-4c6d-815a-ac1e30440ec6