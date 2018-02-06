#! /bin/sh -
echo "Getting list of users"
IAM_USERS=$(aws iam list-users)
USER_NAMES=$(echo $IAM_USERS | jq ".\"Users\" | .[].\"UserName\"")
USER_ARNS=$(echo $IAM_USERS | jq ".\"Users\" | .[].\"Arn\"")

echo "Getting list of groups"
IAM_GROUPS=$(aws iam list-groups)
GROUP_NAMES=$(echo $IAM_GROUPS | jq ".\"Groups\" | .[].\"GroupName\"")
GROUP_ARNS=$(echo $IAM_GROUPS | jq ".\"Groups\" | .[].\"Arn\"")

echo "Getting list of roles"
IAM_ROLES=$(aws iam list-roles)
ROLE_NAMES=$(echo $IAM_ROLES | jq ".\"Roles\" | .[].\"RoleName\"") ROLE_ARNS=$(echo $IAM_ROLES | jq ".\"Roles\" | .[].\"Arn\"")

echo "Getting list of policies"
IAM_POLICIES=$(aws iam list-policies --only-attached)
POLICY_NAMES=$(echo $IAM_POLICIES | jq ".\"Policies\" | .[].\"PolicyName\"")
POLICY_ARNS=$(echo $IAM_POLICIES | jq ".\"Policies\" | .[].\"Arn\"")

nodeName () {
  echo $1 | tr -d ".,-/:\""
}

nodeExists () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

addNodes () {
  NODETYPE=$1; shift
  SHAPE=$1; shift
  ENTITY_ARRAY=$1; shift

  echo "Processing $NODETYPE"
  for ENTITY_NAME in $ENTITY_ARRAY; do
    echo "  $ENTITY_NAME"
    NODE_NAME=$(nodeName $ENTITY_NAME)
    echo "  ${NODETYPE}_${NODE_NAME} [label=$ENTITY_NAME,shape=$SHAPE]" >> iam_graph.gv
    CLEAN_ENTITY_NAME=$(echo $ENTITY_NAME | tr -d "\"")

    local i=1
    while [ $i -le $# ]; do
      IAM_COMMAND=$(eval echo \${$i}); let i=i+1
      IAM_COMMAND_PARAMS=$(eval echo \${$i} | sed "s/__CLEAN_NAME__/$CLEAN_ENTITY_NAME/g"); let i=i+1
      JQ_FILTER=$(eval echo \${$i}); let i=i+1
      TARGET_NODE_TYPE=$(eval echo \${$i}); let i=i+1
      CREATE_NODES=$(eval echo \${$i}); let i=i+1
      NODE_SHAPE=$(eval echo \${$i}); let i=i+1
      NODE_COLOR=$(eval echo \${$i}); let i=i+1
      addEdges $NODETYPE $ENTITY_NAME $IAM_COMMAND "$IAM_COMMAND_PARAMS" "$JQ_FILTER" $TARGET_NODE_TYPE $CREATE_NODES $NODE_SHAPE $NODE_COLOR
    done
  done
}

addEdges () {
#$1 = node type, e.g. policy, user, ... - passed internally
#$2 = source node name - passed internally
#$3 = iam command
#$4 = iam command parameters
#$5 = jq filter
#$6 = target node type
#$7 = boolean to create new nodes
#$8 = node shape
#$9 = color

  ENTITY_NODE_NAME=$(nodeName $2)
  IAM_LIST=$(aws iam $3 $4)
  LIST=$(echo $IAM_LIST | jq "$5")
  for ITEM in $LIST; do
    echo "    Attaching $6 $ITEM"
    ITEM_NODE_NAME=$(nodeName $ITEM)
    if [ $7 == 1 ]; then
      echo "  ${6}_${ITEM_NODE_NAME} [label=$ITEM,shape=$8,color=\"$9\"]" >> iam_graph.gv
    fi
    echo "  ${1}_${ENTITY_NODE_NAME} -> ${6}_${ITEM_NODE_NAME}" >> iam_graph.gv
  done

}

echo "digraph iam {" > iam_graph.gv

addNodes group circle "$GROUP_NAMES" \
  list-group-policies "--group-name __CLEAN_NAME__" ".\"PolicyNames\" | .[]" policy 1 note gray \
  list-attached-group-policies "--group-name __CLEAN_NAME__" ".\"AttachedPolicies\" | .[].\"PolicyName\"" policy 0 . .

addNodes user egg "$USER_NAMES" \
  list-user-policies "--user-name __CLEAN_NAME__" ".\"PolicyNames\" | .[]" policy 1 note gray \
  list-attached-user-policies  "--user-name __CLEAN_NAME__" ".\"AttachedPolicies\" | .[].\"PolicyName\"" policy 0 . . \
  list-groups-for-user "--user-name __CLEAN_NAME__" ".\"Groups\" | .[].\"GroupName\"" group 0 . .

addNodes policy note "$POLICY_NAMES"

addNodes role ellipse "$ROLE_NAMES" \
  list-role-policies "--role-name __CLEAN_NAME__" ".\"PolicyNames\" | .[]" policy 1 note gray \
  list-attached-role-policies  "--role-name __CLEAN_NAME__" ".\"AttachedPolicies\" | .[].\"PolicyName\"" policy 0 . .
  
echo "}" >> iam_graph.gv
circo iam_graph.gv -Tpdf > iam_graph.pdf
