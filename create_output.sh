#!/bin/sh
VER=v1.1
FILE_NAMES=("wrightwood_rpmtif_chicago" "riverside_multitwnmuni" "hyde_park_noexe_chicago" "cicero" "kinzie_nonrpmtif_chicago" "evanston")
PINS_14=("14294070931001" "15361000280000" "20114070180000" "16291280010000" "16123090200000" "10132040060000")

## SET THE VALUES ABOVE

if [ -d "outputs/$VER" ]; then
  echo "folder for version $VER exists"
  else
  mkdir "outputs/$VER"
  echo "folder for version $VER created"
fi

for ((i = 0; i < ${#FILE_NAMES[@]}; i++)) 
  do 
    PIN_14=${PINS_14[$i]}
    FILE_NAME=${FILE_NAMES[$i]}
    sed -i "" "33s/.*/pin_14 <- \"$PIN_14\"/" ptaxsim_explainer_update.qmd

    echo "updated pin in qmd"

    if [ -d "outputs/$VER/$FILE_NAME" ]; then
      echo "folder for $FILE_NAME exists, overwriting"
      else
      mkdir "outputs/$VER/$FILE_NAME"
      echo "folder for $FILE_NAME created"
    fi  

    quarto render ptaxsim_explainer_update.qmd
    mv ptaxsim_explainer_update.html outputs/$VER/$FILE_NAME/ptaxsim_explainer_update.html
    mv ptaxsim_explainer_update_files outputs/$VER/$FILE_NAME/ptaxsim_explainer_update_files
  
  done

echo "Done!"

# pin_14 <- "20114070180000" # Hyde Park, Chicago
# pin_14 <- "15361000280000" # Riverside
# pin_14 <- "16291280010000" # Cicero
# pin_14 <- "14294070931001" # Wrightwood, Chicago - TIF
# pin_14 <- "16123090200000" # Kinzie - TIF