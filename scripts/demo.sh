#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Multi Token Demo Script${NC}"
echo -e "${YELLOW}=========================${NC}"
echo ""

# Check if local replica is running
if ! dfx ping > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: DFX is not running${NC}"
    echo -e "${YELLOW}Please run 'yarn local' first to start the development environment${NC}"
    exit 1
fi

# Check if canisters are deployed
dfx canister id multi_backend > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: Canisters are not deployed${NC}"
    echo -e "${YELLOW}Please run 'yarn local' first to deploy the canisters${NC}"
    exit 1
fi

# Check if frontend is running
if ! curl -s http://localhost:5173 > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Warning: Frontend is not running at http://localhost:5173${NC}"
    echo -e "${YELLOW}The demo will continue, but you won't see UI updates${NC}"
    echo ""
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    npm install
fi

# Run the demo script
echo -e "${GREEN}✅ Environment is ready!${NC}"
echo -e "${GREEN}Running demo operations...${NC}"
echo ""

# Use npx tsx instead of ts-node
npx tsx scripts/demo-setup.ts

echo ""
echo -e "${GREEN}Demo complete!${NC}"
if curl -s http://localhost:5173 > /dev/null 2>&1; then
    echo -e "${GREEN}Check your frontend at http://localhost:5173${NC}"
fi