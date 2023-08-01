# ptax-project-update

__THIS REPO IS NOW INACTIVE, FOLLOW THE LINK BELOW FOR UP TO DATE REPO__  
[https://github.com/dfsnow/ptax-project-update](https://github.com/dfsnow/ptax-project-update)

v1.1

## Explainer

The main files that create the explainers are 
- `ptaxsim_explainer_update.qmd`
- `maps.R`
- `helper_funcs.r`

To create your own explainer - 
- Clone the repo
- Download the ptaxsim database from [here](https://gitlab.com/ccao-data-science---modeling/packages/ptaxsim#database-installation)
- In the shell script `create_output.sh`, change `FILE_NAMES` var to a reasonable file name, and add the 14 digit, non-spaced, Parcel PIN to the `PINS_14` var
  - If adding more than 1, ensure that the `FILE_NAMES` and `PINS_14` are in order
- Run `create_output.sh`, the files will be added to `outputs/v1.1/<FILE_NAMES>`

To preview the files already present use [htmlpreview.github.io/?](htmlpreview.github.io/?)  
Eg, to preview the PIN for hyde park, [click here](https://htmlpreview.github.io/?https://github.com/divij-sinha/ptax-project-update/blob/main/outputs/v1.1/hyde_park_noexe_chicago/ptaxsim_explainer_update.html)

## Map Options

To preview possible map options, [click here](https://htmlpreview.github.io/?https://github.com/divij-sinha/ptax-project-update/blob/main/map_options/map_options.html)
