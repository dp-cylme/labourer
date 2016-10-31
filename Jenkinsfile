#!/usr/bin/env groovy

node {
  def project = 'pinacta'
  def projectId = '148111'
  def appName = 'labourer'
  def feSvcName = "${appName}"
  def imageTag = "gcr.io/${project}-${projectId}/${appName}:${env.BRANCH_NAME}.${env.BUILD_NUMBER}"
  def protocVersion = "3.1.0"
  def protoc = "protoc-${protocVersion}"

  checkout scm

  stage 'Install stack'
  sh("curl -sSL https://get.haskellstack.org/ | sh")

  stage 'Load git submodules'
  sh("git submodule init")
  sh("git submodule update")

  stage 'Install protoc'
  sh("apt-get install unzip")
  sh("wget https://github.com/google/protobuf/releases/download/v${protocVersion}/${protoc}-linux-x86_64.zip")
  sh("unzip ${protoc}-linux-x86_64.zip")
  sh("mv bin/protoc /usr/bin/")

  stage 'Install project global dependencies'
  sh("apt-get install libtinfo-dev")

  try {
      unstash 'stack'
  } catch(ex) {
   println(ex.toString())
   stage 'Install GHC'
   sh("stack setup")
  }

  stage 'Build project'
  sh("stack build")

  stage 'Run tests'
  sh("stack test")

  stage 'Create docker image'
  sh("stack image container")

  stage 'Create tag of image'
  sh("docker tag ${project}/${appName} ${imageTag}")

  stage 'Push image to registry'
  sh("gcloud docker push ${imageTag}")

  stage "Deploy Application"
  switch (env.BRANCH_NAME) {
    // Roll out to production
    case "master":
        sh("ls ./k8s/production")
        // Change deployed image in staging to the one we just built
        sh("sed -i.bak 's#gcr.io/pinacta-147615/labourer:latest#${imageTag}#' k8s/production/*.yaml")
        sh("kubectl --namespace=production apply -f k8s/services/")
        sh("kubectl --namespace=production apply -f k8s/production/")
        sh("echo http://`kubectl --namespace=production get service/${feSvcName} --output=json | jq -r '.status.loadBalancer.ingress[0].ip'` > ${feSvcName}")
        break

    // Roll out a dev environment
    default:
        // Create namespace if it doesn't exist
        sh("kubectl get ns ${env.BRANCH_NAME} || kubectl create ns ${env.BRANCH_NAME}")
        // Don't use public load balancing for development branches
        sh("sed -i.bak 's#LoadBalancer#ClusterIP#' ./k8s/services/frontend.yaml")
        sh("sed -i.bak 's#gcr.io/cloud-solutions-images/gceme:1.0.0#${imageTag}#' ./k8s/dev/*.yaml")
        sh("kubectl --namespace=${env.BRANCH_NAME} apply -f k8s/services/")
        sh("kubectl --namespace=${env.BRANCH_NAME} apply -f k8s/dev/")
        echo 'To access your environment run `kubectl proxy`'
        echo "Then access your service via http://localhost:8001/api/v1/proxy/namespaces/${env.BRANCH_NAME}/services/${feSvcName}:80/"
  }
}
