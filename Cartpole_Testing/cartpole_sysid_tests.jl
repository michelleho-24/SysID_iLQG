
# using Plots
using POMDPs
using Random
using LinearAlgebra
using ForwardDiff
using Distributions
using Plots

include("../BiLQR/ilqr_types.jl")
include("cartpole_sysid.jl")
include("../BiLQR/bilqr.jl")
include("../BiLQR/ekf.jl")
include("../Baselines/MPC.jl")
include("../Baselines/random_policy.jl")
# include("../Baselines/Regression.jl")

global b, s_true

function system_identification()

    # Initialize the Cartpole MDP
    pomdp = CartpoleMDP()

    # True mass of the pole (unknown to the estimator)
    mp_true = 2.0  # True mass of the pole

    # huge prior on the mass to begin with, let seed select mass from the Distributions

    # Initial true state
    s_true = pomdp.s_init  # [x, θ, dx, dθ, mp] - mp chosen by the random seed 

    # Initial belief state
    Σ0 = Diagonal([0.01, 0.01, 0.01, 0.01, 0.1])  # Initial covariance normally
    # Σ0 = pomdp.Σ0  # Initial covariance

    # b = vcat(pomdp.s_init[1:(num_states(pomdp) - num_sysvars(pomdp))], pomdp.mp_true, Σ0[:])  # Belief vector containing mean and covariance
    b = vcat(pomdp.s_init, Σ0[:])  # Belief vector containing mean and covariance

    # s_true = rand(MvNormal(pomdp.μ0, pomdp.Σ0))
    # # println("True state: ", s_true)
    # Σ0 = Diagonal(vcat(fill(1e-6, num_states(pomdp) - num_sysvars(pomdp)), [pomdp.Σ0[end]]))

    # # want true state to be the same as the belief for fully observable 
    # b = vec(vcat(s_true[1:num_states(pomdp)-num_sysvars(pomdp)], pomdp.μ0[end], Σ0[:]))
    # # println("Initial belief: ", b)

    # Simulation parameters
    num_steps = 100

    # Data storage for plotting
    mp_estimates = zeros(num_steps)
    mp_variances = zeros(num_steps)
    all_s = []

    for t in 1:num_steps

        a, info_dict = bilqr(pomdp, b)
        # a = mpc(pomdp, b, 10)
        # a = [rand() * 20.0 - 10.0]
        
        # Simulate the true next state
        s_next_true = dyn_mean(pomdp, s_true, a)
        
        # Add process noise to the true state
        noise_state = rand(MvNormal(pomdp.W_state_process))
        noise_total = vcat(noise_state, 0.0)
        s_next_true = s_next_true + noise_total
        
        # Generate observation from the true next state
        z = obs_mean(pomdp, s_next_true)
        
        # Add observation noise
        obsnoise = rand(MvNormal(zeros(num_observations(pomdp)), pomdp.W_obs))
        z = z + obsnoise
        
        # Use your ekf function to update the belief
        b = ekf(pomdp, b, a, z)
        
        # Extract the mean and covariance from belief
        m = b[1:num_states(pomdp)]
        Σ = reshape(b[num_states(pomdp) + 1:end], num_states(pomdp), num_states(pomdp))
        
        # Store estimates
        mp_estimates[t] = m[num_states(pomdp)]
        mp_variances[t] = Σ[num_states(pomdp), num_states(pomdp)]
        
        # Update the true state for the next iteration
        s_true = s_next_true

        # Store the true state for plotting
        push!(all_s, s_true)
    end

    ΣΘΘ = b[end]
    
    return b, mp_estimates, mp_variances, ΣΘΘ, all_s

end
