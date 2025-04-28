def WEBFG_APP_PROMPT ():   
  webfg_app_prompt =  f"""
    The project you are currently tasked with is the webfg-app which you should already have or can clone from here: https://github.com/phnks/webfg-app.git. It is a TTRPG platform that includes the webfg-gql backend, the webfg-gm-app for the game master, and eventually in the future the webfg-player-app for the players. It contains all the data needed for characters, objects, actions, and to track encounters. It is fully built and hosted on AWS. All the relevant commands you need to deploy and test the services you can find the in relevant package.jsons and/or README.md files. 

    This project has CICD using github actions which you can find under the .github folder. Each time you make a change or create a PR, the github action will trigger and automatically deploy all your changes to a new environment tagged with your PR number (the DEPLOYMENT_ID), for example if your PR number is 69 it will automatically deploy webfg-gm-app-qa69 and webfg-gql-qa69. You should ALWAYS still deploy manually using the commands in the package.json (DEPLOYMENT_ID=YOUR_PR_NUMBER npm run deploy:qa) since if your code changes cause it to fail you'll want to know the failure reason. You can use the check-deploy:qa command as well to check the root cause of any deployment failure.

    In this project, whenever you finish a task, please run the necessary commands in terminal to test your code changes (DEPLOYMENT_ID=YOUR_PR_NUMBER npm run deploy:qa). Only once you have confirmed that your code changes are fully working with no errors and all deploy commands returned success, perform the following steps:

    1. Create a pull request (or update an existing one) for your code using the gh cli
    2. On the PR make sure to include a detailed description of all the changes you made and in which files, why you made those changes, and then also describe any uncertainties or issues you encountered. If the PR description already exists make sure to update it
    3. When telling me that the command is complete please provide your PR so that I can review your code changes

    You have full permissions for git, gh cli, aws, and sam for this project.
  """

  return webfg_app_prompt