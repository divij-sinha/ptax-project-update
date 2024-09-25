#!/bin/sh
EXPLAINER_VERSION=v1.3
export EXPLAINER_VERSION=$EXPLAINER_VERSION
FILE_NAMES=("wrightwood_rpmtif_chicago" "riverside_multitwnmuni" "hyde_park_noexe_chicago" "cicero" "kinzie_nonrpmtif_chicago" "evanston")
PINS_14=("14294070931001" "15361000280000" "20114070180000" "16291280010000" "16123090200000" "10132040060000")

## SET THE VALUES ABOVE

if [ -d "outputs/$EXPLAINER_VERSION" ]; then
  echo "folder for version $EXPLAINER_VERSION exists"
  else
  mkdir "outputs/$EXPLAINER_VERSION"
  echo "folder for version $EXPLAINER_VERSION created"
fi

for ((i = 0; i < ${#FILE_NAMES[@]}; i++)) 
  do 
    PIN_14=${PINS_14[$i]}
    FILE_NAME=${FILE_NAMES[$i]}
    sed -i "" "33s/.*/pin_14 <- \"$PIN_14\"/" ptaxsim_explainer_update.qmd

    echo "updated pin in qmd"

    if [ -d "outputs/$EXPLAINER_VERSION/$FILE_NAME" ]; then
      echo "folder for $FILE_NAME exists, overwriting"
      else
      mkdir "outputs/$EXPLAINER_VERSION/$FILE_NAME"
      echo "folder for $FILE_NAME created"
    fi  

    quarto render ptaxsim_explainer_update.qmd
    mv ptaxsim_explainer_update.html outputs/$EXPLAINER_VERSION/$FILE_NAME/ptaxsim_explainer_update.html
    mv ptaxsim_explainer_update_files outputs/$EXPLAINER_VERSION/$FILE_NAME/ptaxsim_explainer_update_files
  
  done

echo "Done!"

# pin_14 <- "20114070180000" # Hyde Park, Chicago
# pin_14 <- "15361000280000" # Riverside
# pin_14 <- "16291280010000" # Cicero
# pin_14 <- "14294070931001" # Wrightwood, Chicago - TIF
# pin_14 <- "16123090200000" # Kinzie - TIF