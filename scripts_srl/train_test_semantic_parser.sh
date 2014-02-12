#!/bin/bash

# Root folder where TurboParser is installed.
root_folder="`cd $(dirname $0);cd ..;pwd`"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${root_folder}/deps/local/lib"

# Set options.
language=$1 # Example: "slovene" or "english".
train_algorithm=svm_mira # Training algorithm.
train_algorithm_pruner=crf_mira # Training algorithm for pruner.
num_epochs=10 # Number of training epochs.
num_epochs_pruner=10 # Number of training epochs for the pruner.
regularization_parameter=0.001 # The C parameter in MIRA.
regularization_parameter_pruner=1e12 # Same for the pruner.
train=false #true
test=true
prune=true # This will revert to false if model_type=basic.
train_external_pruner=false # If true, the pruner is trained separately.
posterior_threshold=0.0001 # Posterior probability threshold for the pruner.
pruner_max_arguments=20 # Maximum number of candidate heads allowed by the pruner.
labeled=true # Output semantic labels.
case_sensitive=false # Distinguish word upper/lower case.
model_type=basic # Parts used in the model (subset of "af+cs+gp+as+hb+np+dp").
                    # Some shortcuts are: "standard" (means "af+cs+gp");
                    # "basic" (means "af"); and "full" (means "af+cs+gp+as+hb").
                    # Currently, flags np+dp are not recommended because they
                    # make the parser a lot slower.
train_cost_false_positives=$2
train_cost_false_negatives=$3
allow_self_loops=true

if [ "${model_type}" == "basic" ]
then
    echo "Reverting prune to false..."
    prune=false
fi

suffix=parser_pruned-${prune}_model-${model_type}
suffix_pruner=parser_pruner_C-${regularization_parameter_pruner}

# Set path folders.
path_bin=${root_folder} # Folder containing the binary.
path_data=${root_folder}/srl/data/${language} # Folder with the data.
path_models=${root_folder}/srl/models/${language} # Folder where models are stored.
path_results=${root_folder}/srl/results/${language} # Folder for the results.

# Create folders if they don't exist.
mkdir -p ${path_data}
mkdir -p ${path_models}
mkdir -p ${path_results}

# Set file paths. Allow multiple test files.
file_model=${path_models}/${language}_${suffix}.model
file_pruner_model=${path_models}/${language}_${suffix_pruner}.model
file_results=${path_results}/${language}_${suffix}.txt
file_pruner_results=${path_results}/${language}_${suffix_pruner}.txt

if [ "$language" == "english" ]
then
    file_train=${path_data}/${language}_train.conll2008
    files_test[0]=${path_data}/${language}_test.conll2008
    files_test[1]=${path_data}/${language}_devel.conll2008
    files_test[2]=${path_data}/${language}_test.conll2008.MST
    files_test[3]=${path_data}/${language}_devel.conll2008.MST
else
    file_train=${path_data}/${language}_train.conll2008
    file_test=${path_data}/${language}_test.conll2008
    files_test[0]=${file_test}
fi

# Obtain a prediction file path for each test file.
for (( i=0; i<${#files_test[*]}; i++ ))
do
    file_test=${files_test[$i]}
    file_prediction=${file_test}.${suffix}.pred
    file_pruner_prediction=${file_test}.${suffix_pruner}.pred
    files_prediction[$i]=${file_prediction}
    files_pruner_prediction[$i]=${file_pruner_prediction}
done

################################################
# Train the pruner model.
################################################

if ${train_external_pruner}
then
    echo "Training pruner..."
    ${path_bin}/TurboSemanticParser \
        --train \
        --train_epochs=${num_epochs_pruner} \
        --file_model=${file_pruner_model} \
        --file_train=${file_train} \
        --model_type=basic \
        --labeled=false \
        --prune_basic=false \
        --only_supported_features \
        --form_case_sensitive=${case_sensitive} \
        --train_algorithm=${train_algorithm_pruner} \
        --train_regularization_constant=${regularization_parameter_pruner} \
        --train_cost_false_positives=${train_cost_false_positives} \
        --train_cost_false_negatives=${train_cost_false_negatives} \
        --allow_self_loops=${allow_self_loops} \
        --logtostderr

    rm -f ${file_pruner_results}
    for (( i=0; i<${#files_test[*]}; i++ ))
    do
        file_test=${files_test[$i]}
        file_pruner_prediction=${files_pruner_prediction[$i]}

        echo ""
        echo "Testing pruner on ${file_test}..."
        ${path_bin}/TurboSemanticParser \
            --test \
            --evaluate \
            --file_model=${file_pruner_model} \
            --file_test=${file_test} \
            --file_prediction=${file_pruner_prediction} \
            --logtostderr

        echo ""
        echo "Evaluating pruner..."
        touch ${file_pruner_results}
        perl eval08.pl -q -g ${file_test} -s ${file_pruner_prediction} | grep -A7 'SEMANTIC SCORES:' \
            >> ${file_pruner_results}
        cat ${file_pruner_results}
    done
fi

################################################
# Train the parser.
################################################

if $train
then
    if $train_external_pruner
    then
        # The pruner was already trained. Just set the external pruner
        # to the model that was obtained and train the parser.
        echo "Training..."
        ${path_bin}/TurboSemanticParser \
            --train \
            --train_epochs=${num_epochs} \
            --file_model=${file_model} \
            --file_train=${file_train} \
            --labeled=${labeled} \
            --prune_basic=${prune} \
            --pruner_posterior_threshold=${posterior_threshold} \
            --pruner_max_arguments=${pruner_max_arguments} \
            --use_pretrained_pruner \
            --file_pruner_model=${file_pruner_model} \
            --form_case_sensitive=${case_sensitive} \
            --train_algorithm=${train_algorithm} \
            --train_regularization_constant=${regularization_parameter} \
            --train_cost_false_positives=${train_cost_false_positives} \
            --train_cost_false_negatives=${train_cost_false_negatives} \
            --model_type=${model_type} \
            --allow_self_loops=${allow_self_loops} \
            --logtostderr
    else
        # Train a pruner along with the parser.
        ${path_bin}/TurboSemanticParser \
            --train \
            --train_epochs=${num_epochs} \
            --file_model=${file_model} \
            --file_train=${file_train} \
            --labeled=${labeled} \
            --form_case_sensitive=${case_sensitive} \
            --train_algorithm=${train_algorithm} \
            --train_regularization_constant=${regularization_parameter} \
            --train_cost_false_positives=${train_cost_false_positives} \
            --train_cost_false_negatives=${train_cost_false_negatives} \
            --model_type=${model_type} \
            --prune_basic=${prune} \
            --pruner_posterior_threshold=${posterior_threshold} \
            --pruner_max_arguments=${pruner_max_arguments} \
            --pruner_train_epochs=${num_epochs_pruner} \
            --pruner_train_algorithm=${train_algorithm_pruner} \
            --pruner_train_regularization_constant=${regularization_parameter_pruner} \
            --allow_self_loops=${allow_self_loops} \
            --logtostderr
    fi
fi

# move above:
#            --pruner_train_cost_false_positives=${train_cost_false_positives_pruner} \
#            --pruner_train_cost_false_negatives=${train_cost_false_negatives_pruner} \


################################################
# Test the parser.
################################################

if $test
then

    rm -f ${file_results}
    for (( i=0; i<${#files_test[*]}; i++ ))
    do
        file_test=${files_test[$i]}
        file_prediction=${files_prediction[$i]}

        echo ""
        echo "Testing on ${file_test}..."
        ${path_bin}/TurboSemanticParser \
            --test \
            --evaluate \
            --file_model=${file_model} \
            --file_test=${file_test} \
            --file_prediction=${file_prediction} \
            --logtostderr

        echo ""
        echo "Evaluating..."
        touch ${file_results}
        perl eval08.pl -q -g ${file_test} -s ${file_prediction} | grep -A7 'SEMANTIC SCORES:' \
            >> ${file_results}
        cat ${file_results}
    done
fi